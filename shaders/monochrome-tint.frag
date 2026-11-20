#version 440

// Tint only the desaturated parts of an icon: white/grey artwork follows the
// Omarchy accent, while genuinely colored pixels keep their own palette.
// Sampled from a hidden Image supplied by BarWidget.qml.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tintColor;
};

layout(binding = 1) uniform sampler2D sourceItem;

void main() {
    vec4 sampleColor = texture(sourceItem, qt_TexCoord0);
    float hi = max(sampleColor.r, max(sampleColor.g, sampleColor.b));
    float lo = min(sampleColor.r, min(sampleColor.g, sampleColor.b));

    // Pure greys (and white) have zero saturation; smoothstep keeps the
    // transition soft across antialiased edges and slightly tinted artwork.
    float mono = 1.0 - smoothstep(0.04, 0.18, hi - lo);

    // Scale by brightness so white becomes the accent and darker greys stay
    // proportionally darker. Alpha is preserved.
    vec3 tinted = tintColor.rgb * hi;
    fragColor = vec4(mix(sampleColor.rgb, tinted, mono), sampleColor.a) * qt_Opacity;
}
