#version 330 core

in vec3 v_normal;
in vec2 v_uv;

uniform sampler2D u_albedo;
uniform vec4 u_base_color;
uniform vec2 u_uv_scale;
uniform float u_metallic;
uniform float u_roughness;
uniform vec3 u_emissive;

out vec4 FragColor;

void main() {
    vec3 normal_tint = normalize(v_normal) * 0.5 + 0.5;
    vec4 albedo = texture(u_albedo, v_uv * u_uv_scale) * u_base_color;
    vec3 lit = albedo.rgb * (0.35 + 0.65 * normal_tint.z) + u_emissive;
    FragColor = vec4(lit, albedo.a);
}
