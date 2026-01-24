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

uniform vec3 lightPos;
uniform vec3 objectColor;
uniform vec3 lightColor;
uniform vec3 r_viewPos;

uniform Material material;

void main() {
    vec3 ambient = lightColor * material.ambient;

    vec3 norm = normalize(Normal);
    vec3 lightDir = normalize(lightPos - FragPos);

    float diff = max(dot(norm, lightDir), 0.0);
    vec3 diffuse = lightColor * (diff * material.diffuse);

    vec3 viewDir = normalize(r_viewPos - FragPos);
    vec3 reflectDir = reflect(-lightDir, norm);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), material.shininess);

    vec3 specular = lightColor * (spec * material.specular);
    vec3 color = ambient + diffuse + specular;

    color += TexCoord.x * 0.01 + TexCoord.y * 0.01;
    FragColor = vec4(color, 1.0);
}
