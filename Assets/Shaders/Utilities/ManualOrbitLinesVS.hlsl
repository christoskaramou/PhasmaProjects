struct ManualOrbitPushConstants
{
    float4x4 viewProjection;
    float4 offset;
    float4 color;
};

[[vk::push_constant]] ManualOrbitPushConstants pc;

struct VS_INPUT_ManualOrbitLine
{
    float3 position : POSITION;
};

struct PS_INPUT_ManualOrbitLine
{
    float4 color : COLOR0;
    float4 position : SV_POSITION;
};

PS_INPUT_ManualOrbitLine mainVS(VS_INPUT_ManualOrbitLine input)
{
    PS_INPUT_ManualOrbitLine output;
    float3 worldPosition = input.position + pc.offset.xyz;
    output.position = mul(float4(worldPosition, 1.0f), pc.viewProjection);
    output.color = pc.color;
    return output;
}
