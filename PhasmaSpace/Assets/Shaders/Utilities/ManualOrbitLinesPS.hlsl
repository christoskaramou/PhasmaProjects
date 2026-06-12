struct ManualOrbitPushConstants
{
    float4x4 viewProjection;
    float4 offset;
    float4 color;
};

[[vk::push_constant]] ManualOrbitPushConstants pc;

struct PS_INPUT_ManualOrbitLine
{
    float4 color : COLOR0;
    float4 position : SV_POSITION;
};

struct PS_OUTPUT_ManualOrbitLine
{
    float4 color : SV_TARGET;
};

PS_OUTPUT_ManualOrbitLine mainPS(PS_INPUT_ManualOrbitLine input)
{
    PS_OUTPUT_ManualOrbitLine output;
    output.color = input.color;
    return output;
}
