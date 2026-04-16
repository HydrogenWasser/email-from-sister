shader_type canvas_item;

// 简化版 CRT 效果
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float shake_intensity : hint_range(0.0, 0.1) = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    vec2 uv = UV;
    
    // 屏幕抖动
    float shake_x = (random(vec2(TIME, 0.0)) - 0.5) * shake_intensity;
    float shake_y = (random(vec2(0.0, TIME)) - 0.5) * shake_intensity;
    uv += vec2(shake_x, shake_y);
    
    // 采样纹理
    vec3 color = texture(screen_texture, uv).rgb;
    
    // 扫描线
    float scanline = sin(uv.y * 360.0 * 3.14159) * 0.5 + 0.5;
    color *= (1.0 - scanline * scanline_intensity * 0.5);
    
    // Vignette
    vec2 centered = uv - 0.5;
    float dist = length(centered);
    float vig = 1.0 - smoothstep(0.5, 0.9, dist);
    color *= vig;
    
    COLOR = vec4(color, 1.0);
}
