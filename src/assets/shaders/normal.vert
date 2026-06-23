#version 330 core

layout(location = 0) in vec3 aPos;
layout(location = 1) in vec2 aNormal;

uniform mat4 u_view;
uniform mat4 u_model;
uniform mat4 u_projection;

out vec3 vNormal;

vec3 decodeOctNormal(vec2 enc) {
    vec3 n = vec3(enc.x, enc.y, 1.0 - abs(enc.x) - abs(enc.y));
    if (n.z < 0.0) {
        n.xy = (1.0 - abs(n.yx)) * sign(n.xy);
    }
    return normalize(n);
}

void main() {
  gl_Position = u_projection * u_view * u_model * vec4(aPos, 1.0);
  mat3 normal_matrix = transpose(inverse(mat3(u_model)));
  vNormal = normalize(normal_matrix * decodeOctNormal(aNormal));
}
