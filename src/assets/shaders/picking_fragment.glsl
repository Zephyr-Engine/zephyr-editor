#version 330 core
uniform int u_objectId;
out vec4 FragColor;
void main() {
    int id = u_objectId + 1;
    FragColor = vec4(float(id & 0xFF)/255.0, float((id>>8)&0xFF)/255.0, float((id>>16)&0xFF)/255.0, 1.0);
}
