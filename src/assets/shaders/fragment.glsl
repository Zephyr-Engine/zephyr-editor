#version 330 core

in vec3 Normal;
in vec2 TexCoord;

out vec4 FragColor;

void main() {
    vec3 norm = normalize(Normal);
    vec3 color = norm * 0.5 + 0.5;

    color += TexCoord.x * 0.01 + TexCoord.y * 0.01;
    FragColor = vec4(color, 1.0);
}
