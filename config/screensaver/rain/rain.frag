// The rain face's cells (RainFace.qml), all drawn in one pass: each cell's glyph from the atlas (every glyph once, in
// white, a cell apart), in the cell's colour over the background. The cells come as a small image, two pixels a cell:
// the colour, then the glyph's number (1… in red, 0 none).
// Compiled with qt6-qtshadertools: qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o rain.frag.qsb rain.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 grid;          // columns, rows
    vec2 cell;          // a cell in the item's pixels
    vec2 area;          // the item in its pixels
    float glyphCount;   // in the atlas
    vec4 bg;
};
layout(binding = 1) uniform sampler2D cells;
layout(binding = 2) uniform sampler2D atlas;

void main() {
    vec2 p = qt_TexCoord0 * area;
    vec2 c = min(floor(p / cell), grid - 1.0);
    vec2 inCell = (p - c * cell) / cell;
    float v = (c.y + 0.5) / grid.y;
    vec3 colour = texture(cells, vec2((2.0 * c.x + 0.5) / (2.0 * grid.x), v)).rgb;
    float g = floor(texture(cells, vec2((2.0 * c.x + 1.5) / (2.0 * grid.x), v)).r * 255.0 + 0.5);
    float a = 0.0;
    if (g > 0.0) a = texture(atlas, vec2((g - 1.0 + inCell.x) / glyphCount, inCell.y)).a;
    fragColor = vec4(mix(bg.rgb, colour, a), 1.0) * qt_Opacity;
}
