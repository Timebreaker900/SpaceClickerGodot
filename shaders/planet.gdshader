shader_type canvas_item;
// Macht aus einer flachen Weltkarte eine sich drehende Kugel.
// Für jeden Bildpunkt wird berechnet, welche Stelle der Kugeloberfläche dort
// zu sehen wäre, und die passende Stelle der Karte nachgeschlagen.
// Um die Kugel herum bleibt Platz für einen leuchtenden Schein.

uniform float spin_speed = 0.03;                       // Umdrehungen pro Sekunde
uniform vec3 light_direction = vec3(-0.55, -0.5, 0.7); // woher das Licht kommt
uniform vec4 atmosphere_color : source_color = vec4(0.25, 0.75, 1.0, 1.0);
uniform float planet_size : hint_range(0.5, 1.0) = 0.84; // Anteil der Fläche, den die Kugel füllt

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) / planet_size; // Mittelpunkt = (0,0), Kugelrand = Abstand 1
	float dist = length(p);

	// Schein außerhalb der Kugel: am Rand am hellsten, nach außen auslaufend
	float edge_fade = smoothstep(1.0 / planet_size, 1.0, dist);
	float glow = exp(-(dist - 1.0) * 9.0) * 0.55 * edge_fade;
	vec4 result = vec4(atmosphere_color.rgb, clamp(glow, 0.0, 1.0));

	if (dist < 1.0) {
		float z = sqrt(1.0 - dist * dist);
		vec3 normal = vec3(p, z);         // Richtung der Oberfläche an diesem Punkt

		// Längen- und Breitengrad auf der Kugel -> Position auf der Karte
		float longitude = atan(normal.x, normal.z) / TAU + 0.5 + TIME * spin_speed;
		float latitude = asin(clamp(normal.y, -1.0, 1.0)) / PI + 0.5;
		vec3 surface = textureLod(TEXTURE, vec2(fract(longitude), latitude), 0.0).rgb;

		// Licht: helle Seite, dunkle Seite, leuchtender Rand als Atmosphäre
		float light = clamp(dot(normal, normalize(light_direction)), 0.0, 1.0);
		vec3 color = surface * mix(0.35, 1.1, light);
		color += atmosphere_color.rgb * pow(1.0 - z, 3.0) * 0.6;

		// Weicher Übergang am Kugelrand statt harter Pixelkante
		float inside = smoothstep(1.0, 0.985, dist);
		result = mix(result, vec4(color, 1.0), inside);
	}
	COLOR = result;
}
