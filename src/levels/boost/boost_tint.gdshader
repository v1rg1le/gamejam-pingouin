// =============================================================================
//  boost_tint.gdshader — [BOOST 1.65] recolore les flèches de boost.
// -----------------------------------------------------------------------------
//  Les flèches d'origine (Speed_arrow1/2.png) sont jaunes et rouges. Pour un
//  « spectre » de forces (blanc = nul -> jaune -> orange -> rouge = maximum),
//  on garde le DESSIN (contour noir, reflets, deux tons des chevrons) mais on
//  remplace la couleur par `tint` : chaque pixel prend la teinte voulue,
//  éclaircie ou assombrie selon sa luminosité d'origine. Les fichiers PNG ne
//  sont pas modifiés (consigne : on conserve l'art).
// =============================================================================
shader_type canvas_item;

// couleur de la force du boost (calculée par BoostArea.gd)
uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.1, 1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	// luminosité du pixel d'origine (0 = noir, 1 = blanc)
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	// le contour noir reste noir ; les chevrons gardent leurs deux tons
	// (rouge d'origine ~0.4 -> teinte un peu sombre, jaune ~0.7 -> teinte claire)
	float shade = smoothstep(0.06, 0.8, l);
	vec3 rgb = tint.rgb * (0.45 + 0.75 * shade);
	if (l < 0.06) {
		rgb = vec3(0.0);
	}
	COLOR = vec4(min(rgb, vec3(1.0)), c.a * COLOR.a);
}
