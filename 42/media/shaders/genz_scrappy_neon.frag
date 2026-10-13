#version 110

// GENZ Scrappy neon (card #246) -- vanilla animalEffect.frag + two glow keys on the eye visor.
// The .vert is animalEffect.vert byte for byte (skinning untouched).
//   LIME (Scrappy.png, switched on)   -> strong green glow: key and numbers = genz_neon_bestiario
//                                        (pz-b42-modding section 202), without the rim (the animal
//                                        .vert does not output vertNormalClip)
//   RED  (ScrappyOff.png, shut down)  -> much weaker red glow (GENZ_R_FORCA)
// checar_scrappy_neon.py reads these #defines and checks that each texture lights only the visor.
#define GENZ_B_FORCA   1.60
#define GENZ_B_COR     vec3(0.55, 1.00, 0.04)
#define GENZ_B_COR_NUC vec3(0.55, 1.00, 0.92)
#define GENZ_B_NUC_LO  0.80
#define GENZ_B_NUC_HI  1.00
#define GENZ_B_APAGA   0.45
#define GENZ_B_DIA     0.60
#define GENZ_B_NOITE   1.00
#define GENZ_B_DOM_LO  1.06
#define GENZ_B_DOM_HI  1.30
#define GENZ_B_VS_B    1.15
#define GENZ_B_SAT     0.32
#define GENZ_B_VAL_LO  0.30
#define GENZ_B_VAL_HI  0.55
// red key: r over the larger of g/b well past the amber shoulder lamps (r/g ~1.7), saturated, bright
#define GENZ_R_FORCA   0.35
#define GENZ_R_COR     vec3(1.00, 0.10, 0.06)
#define GENZ_R_DOM_LO  3.00
#define GENZ_R_DOM_HI  5.00
#define GENZ_R_SAT     0.70
#define GENZ_R_VAL_LO  0.50
#define GENZ_R_VAL_HI  0.80

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

	// ---- GENZ neon: only lime lights (g dominating r, above b, saturated, bright) ----
	float bMax = max(texSample.x, max(texSample.y, texSample.z));
	float bMin = min(texSample.x, min(texSample.y, texSample.z));
	float bSat = (bMax - bMin) / max(bMax, 0.0001);
	float bMask = smoothstep(GENZ_B_DOM_LO, GENZ_B_DOM_HI, texSample.y / max(texSample.x, 0.0001))
	            * smoothstep(-0.02, 0.04, texSample.y - texSample.z * GENZ_B_VS_B)
	            * smoothstep(GENZ_B_SAT - 0.06, GENZ_B_SAT + 0.06, bSat)
	            * smoothstep(GENZ_B_VAL_LO, GENZ_B_VAL_HI, bMax);
	// world light on this pixel (0 = dark, 1 = sun): by day the glow adds LESS
	float bLuz = clamp(dot(lighting, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
	float bGanho = mix(GENZ_B_NOITE, GENZ_B_DIA, bLuz);
	float bNucleo = smoothstep(GENZ_B_NUC_LO, GENZ_B_NUC_HI, bMax) * bMask;
	vec3 bCor = mix(GENZ_B_COR, GENZ_B_COR_NUC, bNucleo);
	col *= 1.0 - bMask * GENZ_B_APAGA;
	col += bCor * bMask * bMax * GENZ_B_FORCA * bGanho;
	// ---- red, shut down: same idea, a fraction of the strength ----
	float rMask = smoothstep(GENZ_R_DOM_LO, GENZ_R_DOM_HI, texSample.x / max(max(texSample.y, texSample.z), 0.0001))
	            * smoothstep(GENZ_R_SAT - 0.06, GENZ_R_SAT + 0.06, bSat)
	            * smoothstep(GENZ_R_VAL_LO, GENZ_R_VAL_HI, bMax);
	col += GENZ_R_COR * rMask * bMax * GENZ_R_FORCA * bGanho;
	// ceiling per VECTOR, not per channel: saturates without shifting hue (section 202)
	col /= max(1.0, max(col.r, max(col.g, col.b)));
	// ----------------------------------------------------------------

    vec4 fragCol = vec4(col * vertColour, Alpha * texSample.w);
	gl_FragColor = fragCol;
}
