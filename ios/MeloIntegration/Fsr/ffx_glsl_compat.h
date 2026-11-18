// GLSL 4.50 portability definitions for the MIT-licensed AMD FSR1 GPU header.
// Use full precision, colour-only shaders; no x86 code, AMD ISA or wave ops.
#define FFX_GPU 1
#define FFX_HALF 0
#define FFX_STATIC
#define FFX_PARAMETER_IN in
#define FFX_PARAMETER_OUT out
#define FFX_PARAMETER_INOUT inout
#define FFX_TRUE true
#define FFX_FALSE false
#define FfxBoolean bool
#define FfxFloat32 float
#define FfxFloat32x2 vec2
#define FfxFloat32x3 vec3
#define FfxFloat32x4 vec4
#define FfxUInt32 uint
#define FfxUInt32x2 uvec2
#define FfxUInt32x4 uvec4
#define FfxInt32x2 ivec2
#define ffxAsUInt32 floatBitsToUint
#define ffxAsFloat uintBitsToFloat
#define ffxBroadcast2 vec2
#define ffxBroadcast3 vec3
#define ffxBroadcast4 vec4
#define ffxFract fract
#define ffxMin min
#define ffxMin3(a,b,c) min(a,min(b,c))
#define ffxMax3(a,b,c) max(a,max(b,c))
#define ffxSqrt sqrt
#define ffxSaturate(a) clamp(a,0.0,1.0)
#define ffxReciprocal(a) (1.0/(a))
#define ffxApproximateReciprocal(a) (1.0/(a))
#define ffxApproximateReciprocalMedium(a) (1.0/(a))
#define ffxApproximateReciprocalSquareRoot inversesqrt
#define ffxIsGreaterThanZero(a) max(sign(a),0.0)
#define ffxPackHalf2x16 packHalf2x16
