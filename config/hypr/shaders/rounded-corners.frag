#version 300 es
precision highp float;

in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

// Rounds the desktop corners off in black (like macOS), and tints the screen warm for the night light.
// Values are physical pixels: scale 2.0 → 24 px = 12 px logical.
const float R   = 24.0;  // corner radius
const float TOP = 74.0;  // top bar height (37 * 2); rounding starts at the bar's bottom edge, one per screen in the copy corners.lua writes
const float BAR = 1.0;   // top bar opacity: the top corners continue the bar at the same transparency (hypr/scripts/bar-style writes a copy)
// corners.lua writes copies with these changed: no corners under a fullscreen window, and the night light's colour
// (hypr/scripts/nightlight; Asahi's display driver has no gamma tables, so gammastep and the like can't do it)
const float CORNERS = 1.0;
const vec3 WARM = vec3(1.0);

// 1.0 = black (outside the corner), 0.0 = visible
float corner(vec2 p, vec2 corner, vec2 dir) {
    vec2 q = (p - (corner + dir * R)) * dir;
    if (q.x < 0.0 && q.y < 0.0) {
        return smoothstep(R - 0.7, R + 0.7, length(q));
    }
    return 0.0;
}

void main() {
    vec4 c = texture(tex, v_texcoord);
    vec2 size = vec2(textureSize(tex, 0));
    vec2 p = v_texcoord * size;

    float m = 0.0;
    if (p.y >= TOP) {
        m = max(m, BAR * corner(p, vec2(0.0, TOP),    vec2( 1.0,  1.0)));
        m = max(m, BAR * corner(p, vec2(size.x, TOP), vec2(-1.0,  1.0)));
    }
    m = max(m, corner(p, vec2(0.0, size.y),         vec2( 1.0, -1.0)));
    m = max(m, corner(p, vec2(size.x, size.y),      vec2(-1.0, -1.0)));

    fragColor = vec4(mix(c.rgb * WARM, vec3(0.0), m * CORNERS), c.a);
}
