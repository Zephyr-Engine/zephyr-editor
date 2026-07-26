# Zephyr Editor
The actual editor of Zephyr. 

## Usage
```bash
mkdir zephyr

cd zephyr
git clone git@github.com:Zephyr-Engine/zephyr-runtime.git
git clone git@github.com:Zephyr-Engine/zephyr-editor.git

mkdir game

cd zephyr-editor
zig build run -- create ../game
zig build run -- open ../game
```
