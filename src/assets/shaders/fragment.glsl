#version 330 core

struct Material {
  vec3 ambient;
  vec3 diffuse;
  vec3 specular;
  float shininess;
};

in vec3 Normal;
in vec2 TexCoord;
in vec3 FragPos;

out vec4 FragColor;

uniform vec3 r_viewPos;
uniform Material material;

#include "lighting"

void main() {
    vec3 normal = normalize(Normal);
    vec3 viewDir = normalize(r_viewPos - FragPos);

    vec3 color = calcLighting(normal, viewDir, FragPos, material.ambient, material.diffuse, material.specular, material.shininess);

    // TexCoord used to prevent shader from optimizing out the attribute
    FragColor = vec4(color, 1.0) + vec4(TexCoord, 0.0, 0.0) * 0.0001;
}
