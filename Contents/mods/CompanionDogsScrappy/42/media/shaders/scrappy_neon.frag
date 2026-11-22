#version 110

// Scrappy neon -- vanilla animalEffect.frag + three glow keys.
// The .vert is animalEffect.vert byte for byte (skinning untouched).
//   LIME  (visor, Scrappy.png, on)        -> strong green glow: key and numbers of a plain neon shader
//                                            without the rim (the animal
//                                            .vert does not output vertNormalClip)
//   RED   (visor: alert / shut down)     -> the bright alert red glows as strong as the lime;
//                                            ScrappyOff.png paints a DARKER red (value 0.62), which this
//                                            key only half-passes: ~0.35, the old shut-down glow
//   AMBER (4 back lamps, Scrappy.png, on) -> amber glow; ScrappyOff.png paints them dark
// checar_scrappy_neon.py reads these #defines and counts what each texture lights.
#define SCRAPPY_B_FORCA   1.60
#define SCRAPPY_B_COR     vec3(0.55, 1.00, 0.04)
#define SCRAPPY_B_COR_NUC vec3(0.55, 1.00, 0.92)
#define SCRAPPY_B_NUC_LO  0.80
#define SCRAPPY_B_NUC_HI  1.00
#define SCRAPPY_B_APAGA   0.45
#define SCRAPPY_B_DIA     0.60
#define SCRAPPY_B_NOITE   1.00
#define SCRAPPY_B_DOM_LO  1.06
#define SCRAPPY_B_DOM_HI  1.30
#define SCRAPPY_B_VS_B    1.15
#define SCRAPPY_B_SAT     0.32
#define SCRAPPY_B_VAL_LO  0.30
#define SCRAPPY_B_VAL_HI  0.55
// red key: r over the larger of g/b well past the amber shoulder lamps (r/g ~1.7), saturated, bright
#define SCRAPPY_R_FORCA   1.60
#define SCRAPPY_R_COR     vec3(1.00, 0.10, 0.06)
#define SCRAPPY_R_DOM_LO  3.00
#define SCRAPPY_R_DOM_HI  5.00
#define SCRAPPY_R_SAT     0.70
#define SCRAPPY_R_VAL_LO  0.50
#define SCRAPPY_R_VAL_HI  0.80
// amber key: g/r inside an orange window (lime is > 1, the red visor 0.08), little blue, saturated, bright
#define SCRAPPY_A_FORCA   1.20
#define SCRAPPY_A_COR     vec3(1.00, 0.55, 0.05)
#define SCRAPPY_A_GR_LO   0.40
#define SCRAPPY_A_GR_HI   0.70
#define SCRAPPY_A_BR_MAX  0.20
#define SCRAPPY_A_SAT     0.75
#define SCRAPPY_A_VAL_LO  0.60
#define SCRAPPY_A_VAL_HI  0.85

varying vec3 vertColour;
varying vec3 vertNormal;
varying vec2 texCoords;

uniform sampler2D Texture;
uniform float Alpha;
uniform float LightingAmount;

uniform vec3 TintColour;

uniform vec3 AmbientColour;
uniform vec3 Light0Direction;
uniform vec3 Light0Colour;
uniform vec3 Light1Direction;
uniform vec3 Light1Colour;
uniform vec3 Light2Direction;
uniform vec3 Light2Colour;
uniform vec3 Light3Direction;
uniform vec3 Light3Colour;
uniform vec3 Light4Direction;
uniform vec3 Light4Colour;
uniform float HueChange;

#include "util/math"
#include "util/hueShift"

void main()
{
	vec3 normal = normalize(vertNormal);

	vec4 texSample = texture2D(Texture, texCoords);
	if(texSample.w < 0.01)
	{
	    discard;
	}

	vec3 col = texSample.xyz;

    float dotprod;
    if(HueChange != 0.0)
    {
        col = hueShift(col, HueChange);
    }

	const float QuantiseLevels = 8.0;
	vec3 lighting = vec3(0.0);

	dotprod = max(dot(normal, normalize(Light0Direction)), 0.0);

	lighting += Light0Colour * dotprod;

	dotprod = max(dot(normal, normalize(Light1Direction)), 0.0);

	lighting += Light1Colour * dotprod;

	dotprod = max(dot(normal, normalize(Light2Direction)), 0.0);

	lighting += Light2Colour * dotprod;

	dotprod = max(dot(normal, normalize(Light3Direction)), 0.0);

	lighting += Light3Colour * dotprod;

	dotprod = max(dot(normal, normalize(Light4Direction)), 0.0);

	lighting += Light4Colour * dotprod;

	lighting += AmbientColour;
	lighting.x = min(lighting.x, 1.0);
	lighting.y = min(lighting.y, 1.0);
	lighting.z = min(lighting.z, 1.0);

	vec3 tintColour = TintColour;
	col = vec3(col.x * tintColour.x * lighting.x, col.y * tintColour.y * lighting.y, col.z * tintColour.z * lighting.z);

	// ---- Scrappy neon: only lime lights (g dominating r, above b, saturated, bright) ----
	float bMax = max(texSample.x, max(texSample.y, texSample.z));
	float bMin = min(texSample.x, min(texSample.y, texSample.z));
	float bSat = (bMax - bMin) / max(bMax, 0.0001);
	float bMask = smoothstep(SCRAPPY_B_DOM_LO, SCRAPPY_B_DOM_HI, texSample.y / max(texSample.x, 0.0001))
	            * smoothstep(-0.02, 0.04, texSample.y - texSample.z * SCRAPPY_B_VS_B)
	            * smoothstep(SCRAPPY_B_SAT - 0.06, SCRAPPY_B_SAT + 0.06, bSat)
	            * smoothstep(SCRAPPY_B_VAL_LO, SCRAPPY_B_VAL_HI, bMax);
	// world light on this pixel (0 = dark, 1 = sun): by day the glow adds LESS
	float bLuz = clamp(dot(lighting, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
	float bGanho = mix(SCRAPPY_B_NOITE, SCRAPPY_B_DIA, bLuz);
	float bNucleo = smoothstep(SCRAPPY_B_NUC_LO, SCRAPPY_B_NUC_HI, bMax) * bMask;
	vec3 bCor = mix(SCRAPPY_B_COR, SCRAPPY_B_COR_NUC, bNucleo);
	col *= 1.0 - bMask * SCRAPPY_B_APAGA;
	col += bCor * bMask * bMax * SCRAPPY_B_FORCA * bGanho;
	// ---- red, shut down: same idea, a fraction of the strength ----
	float rMask = smoothstep(SCRAPPY_R_DOM_LO, SCRAPPY_R_DOM_HI, texSample.x / max(max(texSample.y, texSample.z), 0.0001))
	            * smoothstep(SCRAPPY_R_SAT - 0.06, SCRAPPY_R_SAT + 0.06, bSat)
	            * smoothstep(SCRAPPY_R_VAL_LO, SCRAPPY_R_VAL_HI, bMax);
	col += SCRAPPY_R_COR * rMask * bMax * SCRAPPY_R_FORCA * bGanho;
	// ---- amber back lamps ----
	float aGr = texSample.y / max(texSample.x, 0.0001);
	float aMask = smoothstep(SCRAPPY_A_GR_LO - 0.06, SCRAPPY_A_GR_LO + 0.06, aGr)
	            * (1.0 - smoothstep(SCRAPPY_A_GR_HI - 0.06, SCRAPPY_A_GR_HI + 0.06, aGr))
	            * (1.0 - smoothstep(SCRAPPY_A_BR_MAX - 0.05, SCRAPPY_A_BR_MAX + 0.05, texSample.z / max(texSample.x, 0.0001)))
	            * smoothstep(SCRAPPY_A_SAT - 0.06, SCRAPPY_A_SAT + 0.06, bSat)
	            * smoothstep(SCRAPPY_A_VAL_LO, SCRAPPY_A_VAL_HI, bMax);
	col += SCRAPPY_A_COR * aMask * bMax * SCRAPPY_A_FORCA * bGanho;
	// ceiling per VECTOR, not per channel: saturates without shifting hue (section 202)
	col /= max(1.0, max(col.r, max(col.g, col.b)));
	// ----------------------------------------------------------------

    vec4 fragCol = vec4(col * vertColour, Alpha * texSample.w);
	gl_FragColor = fragCol;
}
