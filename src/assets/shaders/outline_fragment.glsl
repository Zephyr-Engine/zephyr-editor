#version 330 core
uniform vec3 u_outlineColor;
out vec4 FragColor;
void main() { FragColor = vec4(u_outlineColor, 1.0); }
