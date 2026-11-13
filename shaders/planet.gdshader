shader_type canvas_item;
// Macht aus einer flachen Weltkarte eine sich drehende Kugel.
// Für jeden Bildpunkt wird berechnet, welche Stelle der Kugeloberfläche dort
// zu sehen wäre, und die passende Stelle der Karte nachgeschlagen.

uniform float spin_speed = 0.03;                       // Umdrehungen pro Sekunde
uniform vec3 light_direction = vec3(-0.55, -0.5, 0.7); // woher das Licht kommt
uniform vec4 atmosphere_color : source_color = vec4(0.35, 0.6, 1.0, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;          // Mittelpunkt = (0,0), Rand = Abstand 1
	float dist_sq = dot(p, p);
	float z = sqrt(max(0.0, 1.0 - dist_sq));
	vec3 normal = vec3(p, z);         // Richtung der Oberfläche an diesem Punkt

	// Längen- und Breitengrad auf der Kugel -> Position auf der Karte
	float longitude = atan(normal.x, normal.z) / TAU + 0.5 + TIME * spin_speed;
	float latitude = asin(clamp(normal.y, -1.0, 1.0)) / PI + 0.5;
	vec3 surface = textureLod(TEXTURE, vec2(fract(longitude), latitude), 0.0).rgb;

	// Licht: helle Seite, dunkle Seite, leuchtender Rand als Atmosphäre
	float light = clamp(dot(normal, normalize(light_direction)), 0.0, 1.0);
	vec3 color = surface * mix(0.35, 1.1, light);
	float rim = pow(1.0 - z, 3.0);
	color += atmosphere_color.rgb * rim * 0.6;

	COLOR = vec4(color, smoothstep(1.0, 0.97, dist_sq));
}
