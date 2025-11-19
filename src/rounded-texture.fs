#version 330

in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec2 rectSize;
uniform float radius;

float sdRoundedBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    // Sample the texture
    vec4 texColor = texture(texture0, fragTexCoord) * fragColor;

    // Use fragTexCoord which is already in 0-1 space
    // Convert to centered pixel coordinates
    vec2 halfSize = rectSize * 0.5;
    vec2 p = (fragTexCoord - 0.5) * rectSize;

    // Signed distance to rounded box
    float d = sdRoundedBox(p, halfSize, radius);

    // Anti-aliased clipping based on pixel size
    float pixelSize = length(fwidth(p));
    float alpha = 1.0 - smoothstep(-pixelSize, pixelSize, d);

    finalColor = vec4(texColor.rgb, texColor.a * alpha);
}
