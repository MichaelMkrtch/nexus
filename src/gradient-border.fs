#version 330

in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform vec2 rectSize;
uniform float radius;
uniform float borderThickness;
uniform vec4 colTL;
uniform vec4 colTR;
uniform vec4 colBL;
uniform vec4 colBR;

float sdRoundedBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    // Safety fallback if uniform fails
    float thick = borderThickness;
    if (thick <= 0.0) thick = 1.0;

    // Use gl_FragCoord for stable 0-1 UV over the render texture
    // Flip Y so gradient matches Raylib's top-down coordinates
    vec2 uv = gl_FragCoord.xy / rectSize;
    uv.y = 1.0 - uv.y;

    vec4 top = mix(colTL, colTR, uv.x);
    vec4 bot = mix(colBL, colBR, uv.x);
    vec4 color = mix(top, bot, uv.y);

    vec2 halfSize = rectSize * 0.5;
    vec2 p = (uv - 0.5) * rectSize;

    // Signed distance to outer rounded box (in pixels)
    float d = sdRoundedBox(p, halfSize, radius);

    // Use derivative-based smoothing for nicer anti-aliased edges.
    // Slightly enlarge the smoothing width to soften the transition.
    float w = fwidth(d) * 2.0;

    // Alpha Outer: 1.0 well inside, 0.0 well outside
    float alphaOuter = 1.0 - smoothstep(0.0 - w, 0.0 + w, d);

    // Alpha Inner: 0.0 well inside hole, 1.0 in the border
    float alphaInner = smoothstep(0.0 - w, 0.0 + w, d + thick);

    // Combine
    float finalAlpha = alphaOuter * alphaInner;

    finalColor = vec4(color.rgb, color.a * finalAlpha);
}

