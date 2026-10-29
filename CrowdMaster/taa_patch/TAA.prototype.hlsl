#include "../Common/Common.hlsl"

struct PushConstants
{
    float2 resolution; // Input resolution
    float2 displaySize; // Output resolution
    float2 jitter;
    float2 padding;
};

[[vk::push_constant]] ConstantBuffer<PushConstants> pc;
[[vk::binding(0)]] Texture2D<float4> in_color : register(t0);
[[vk::binding(1)]] Texture2D<float4> in_history : register(t1);
[[vk::binding(2)]] Texture2D<float2> in_velocity : register(t2);
[[vk::binding(3)]] Texture2D<float> in_depth : register(t3);
[[vk::binding(4)]] SamplerState sampler_linear_clamp : register(s4);
#ifdef HDR_SCENE
[[vk::binding(5)]] [[vk::image_format("rgba16f")]] RWTexture2D<float4> out_color : register(u5);
#else
[[vk::binding(5)]] [[vk::image_format("rgba8")]] RWTexture2D<float4> out_color : register(u5);
#endif

// History is resampled with a 5-tap Catmull-Rom (bilinear re-filtering of the history every frame is what makes
// moving objects go soft: each reprojection is another 2x2 box blur, compounded by the 0.96 feedback).
float3 SampleHistoryCatmullRom(float2 uv)
{
    float2 size = pc.displaySize;
    float2 samplePos = uv * size;
    float2 texPos1 = floor(samplePos - 0.5) + 0.5;
    float2 f = samplePos - texPos1;
    float2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    float2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    float2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    float2 w3 = f * f * (-0.5 + 0.5 * f);
    float2 w12 = w1 + w2;
    float2 offset12 = w2 / w12;
    float2 texPos0 = (texPos1 - 1.0) / size;
    float2 texPos3 = (texPos1 + 2.0) / size;
    float2 texPos12 = (texPos1 + offset12) / size;
    float3 r = 0.0;
    r += in_history.SampleLevel(sampler_linear_clamp, float2(texPos12.x, texPos0.y), 0).rgb * (w12.x * w0.y);
    r += in_history.SampleLevel(sampler_linear_clamp, float2(texPos0.x, texPos12.y), 0).rgb * (w0.x * w12.y);
    r += in_history.SampleLevel(sampler_linear_clamp, float2(texPos12.x, texPos12.y), 0).rgb * (w12.x * w12.y);
    r += in_history.SampleLevel(sampler_linear_clamp, float2(texPos3.x, texPos12.y), 0).rgb * (w3.x * w12.y);
    r += in_history.SampleLevel(sampler_linear_clamp, float2(texPos12.x, texPos3.y), 0).rgb * (w12.x * w3.y);
    float wsum = w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y;
    return max(0.0, r / wsum);
}

float3 RGBToYCoCg(float3 c) { return float3(dot(c, float3(0.25, 0.5, 0.25)), dot(c, float3(0.5, 0.0, -0.5)), dot(c, float3(-0.25, 0.5, -0.25))); }
float3 YCoCgToRGB(float3 c) { return float3(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z); }

float3 ClipAABB(float3 aabbMin, float3 aabbMax, float3 prevSample, float3 avg)
{
    // Clip history to the neighborhood of the current frame
    // This reduces ghosting by rejecting history that is too different from current
    float3 p_clip = 0.5 * (aabbMax + aabbMin);
    float3 e_clip = 0.5 * (aabbMax - aabbMin);

    float3 v_clip = prevSample - p_clip;
    float3 v_unit = v_clip.xyz / e_clip.xyz;
    float3 a_unit = abs(v_unit);
    float ma_unit = max(a_unit.x, max(a_unit.y, a_unit.z));

    if (ma_unit > 1.0)
        return p_clip + v_clip / ma_unit;
    else
        return prevSample;
}

// Tonemap to reduce flickering (Reinhard)
float3 Tonemap(float3 x) { return x / (1.0 + Luminance(x)); }
float3 InverseTonemap(float3 x) { return x / (1.0 - Luminance(x)); }

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    int2 coord = int2(id.xy);
    float2 uv = (float2(coord) + 0.5) / pc.displaySize;

    if (any(uv > 1.0)) return;
    
    // Sample current color with handling for upscaling
    // Since we are upscaling, we sample the low-res input at high-res UVs
    float3 centerColor = in_color.SampleLevel(sampler_linear_clamp, uv, 0).rgb;
    
    // Calculate AABB in the low-res input space
    // We want the 3x3 block of texels in the input image that surround this UV
    float3 colorMin = 10000.0;
    float3 colorMax = -10000.0;
    float3 colorAvg = 0.0;
    float3 m1 = 0.0, m2 = 0.0;          // YCoCg moments for variance clipping
    float closestDepth = 0.0;           // reverse-Z: nearest = largest
    int2 closestOffset = int2(0, 0);

    int2 lowResCenter = int2(floor(uv * pc.resolution));

    [unroll]
    for(int x = -1; x <= 1; ++x)
    {
        [unroll]
        for(int y = -1; y <= 1; ++y)
        {
            float3 neighbor = in_color.Load(int3(lowResCenter + int2(x, y), 0)).rgb;
            colorMin = min(colorMin, neighbor);
            colorMax = max(colorMax, neighbor);
            colorAvg += neighbor;
            float3 yc = RGBToYCoCg(Tonemap(neighbor));
            m1 += yc; m2 += yc * yc;
#if TAA_DEPTH_DILATION
            // needs TAAPass.cpp to bind depth (slot 3) -- see TAA.proposed.diff; unbound -> device crash
            float d = in_depth.Load(int3(lowResCenter + int2(x, y), 0));
            if (d > closestDepth) { closestDepth = d; closestOffset = int2(x, y); }
#else
            // shader-only fallback: longest motion vector in the 3x3 (moving foreground wins over static background)
            float2 vn = in_velocity.Load(int3(lowResCenter + int2(x, y), 0)).xy;
            float l2 = dot(vn, vn);
            if (l2 > closestDepth) { closestDepth = l2; closestOffset = int2(x, y); }
#endif
        }
    }
    colorAvg /= 9.0;
    
    // Simple Unsharp Mask on input
    // Sharpening input helps to keep the detail after temporal blending
    float sharpenStrength = 0.25; // 0.0 - 1.0 (Catmull-Rom history keeps detail; 0.5 over-sharpened edges -> shimmer)
    centerColor = centerColor + (centerColor - colorAvg) * sharpenStrength;
    centerColor = max(0.0, centerColor);

    // Velocity dilation: take the motion vector of the nearest surface in the 3x3 so a moving silhouette (pawns, gate
    // panels, saw blades) reprojects with its own motion instead of the background's -> no smeared/ghosted edges.
    float2 velocity = in_velocity.Load(int3(lowResCenter + closestOffset, 0)).xy;
    
    // Convert to UV space (factor 0.5) and add it to current UV to get previous UV
    // Velocity is from GBuffer (Low Res), stored as (PrevNDC - CurrNDC)
    // Works correctly regardless of resolution as it is screen relative
    float2 historyUV = uv + velocity * 0.5;

    // Out of bounds
    if (any(historyUV < 0.0) || any(historyUV > 1.0))
    {
        out_color[coord] = float4(centerColor, 1.0);
        return;
    }

    float3 historyColor = SampleHistoryCatmullRom(historyUV);

    // Variance clip in tonemapped YCoCg (tighter than the RGB min/max box, which lets stale history through on
    // saturated edges like the red/blue gate panels)
    m1 /= 9.0; m2 /= 9.0;
    float3 sigma = sqrt(max(0.0, m2 - m1 * m1));
    const float gamma = 1.25;
    float3 hY = RGBToYCoCg(Tonemap(historyColor));
    hY = ClipAABB(m1 - gamma * sigma, m1 + gamma * sigma, hY, m1);
    historyColor = InverseTonemap(YCoCgToRGB(hY));

    // Feedback factor
    // Scale velocity by Display Resolution for pixel-accurate motion check in high res
    float velocityLength = length(velocity * pc.displaySize); 
    
    // Feedback: 0.94 when static, easing to 0.85 by 16 px/frame of motion. The old curve (0.96 * (1 - v/100))
    // stayed above 0.9 up to ~6 px/frame, i.e. ~10+ frames of history on everything a runner game moves at,
    // which is the "laggy/blurry" look. Lowering the static weight alone (0.96 -> 0.94) already helps.
    float feedback = lerp(0.94, 0.85, saturate(velocityLength / 16.0));
    
    // Tonemap before blending to reduce fireflies
    float3 tc = Tonemap(centerColor);
    float3 th = Tonemap(historyColor);
    
    // Blend
    float3 result = lerp(tc, th, feedback);
    
    result = InverseTonemap(result);

    out_color[coord] = float4(result, 1.0);
}
