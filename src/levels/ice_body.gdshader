// [GLACE 1.77] Corps des plateformes : glace unie avec de grandes facettes
// très discrètes (demande de l'équipe du 27/11 : « uniformiser la couleur des
// plateformes, leur donner un côté glace, motif léger car on défile vite »).
//
// - La couleur de base vient du Polygon2D (COLOR) : IceStyle.ICE_BODY.
// - Motif = cellules de Voronoï de ~facet_size px (grandes, donc calmes à
//   haute vitesse), chacune un poil plus claire ou plus sombre (± facet_contrast),
//   séparées par de fines fissures claires (crack_strength).
// - Le motif est accroché au MONDE (pas à l'écran) : il défile avec le sol, il
//   ne « nage » pas. Il est calculé par gros pixels de `pixel` px (4 = même
//   gros pixel que le fond), pour rester dans le style pixel art.
shader_type canvas_item;

uniform float facet_size = 420.0;      // taille moyenne d'une facette (px du monde)
uniform float facet_contrast = 0.025;  // écart de luminosité entre facettes
uniform float crack_strength = 0.035;   // éclaircissement des fissures
uniform float crack_width = 4.0;       // largeur des fissures (px du monde)
uniform float pixel = 4.0;             // taille du gros pixel

varying vec2 wpos;

void vertex() {
	// position dans le monde : le motif reste collé au terrain
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

void fragment() {
	// gros pixels, et facettes un peu étirées en biais (comme des plans de
	// glace qui ont glissé) : on tourne et on étire l'espace
	vec2 q = floor(wpos / pixel) * pixel;
	q = vec2(q.x * 0.866 + q.y * 0.5, -q.x * 0.5 + q.y * 0.866);
	q.x *= 0.6;
	vec2 p = q / facet_size;
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 id1 = ip;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 r = g + hash2(ip + g) - fp;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id1 = ip + g;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	float shade = (hash2(id1 * 1.7).x - 0.5) * 2.0 * facet_contrast;
	// distance (en px du monde) à la frontière entre deux facettes
	float border = (sqrt(d2) - sqrt(d1)) * facet_size;
	float crack = 1.0 - step(crack_width, border);
	vec3 c = COLOR.rgb * (1.0 + shade) + vec3(crack * crack_strength);
	COLOR = vec4(c, COLOR.a);
}
