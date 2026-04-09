#version 330 core

layout(location = 0) in vec3 aPos;
layout(location = 1) in vec2 aNormal;

uniform vec2 u_offset;

out vec3 vNormal;

vec3 decodeOctNormal(vec2 enc) {
    vec3 n = vec3(enc.x, enc.y, 1.0 - abs(enc.x) - abs(enc.y));
    if (n.z < 0.0) {
        n.xy = (1.0 - abs(n.yx)) * sign(n.xy);
    }
    return normalize(n);
}

void main() {
  gl_Position = vec4(aPos.x + u_offset.x, aPos.y + u_offset.y, aPos.z, 1.0);
  vNormal = decodeOctNormal(aNormal);
}
