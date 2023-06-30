shader_type sky;
render_mode use_half_res_pass, use_quarter_res_pass;

// These properties are precomputed by the NishitaSky script, and cannot be modified
uniform float precomputed_sun_visible = 1.0;
uniform float precomputed_sun_enabled = 1.0;
uniform mat3 precomputed_moon_dir = mat3(0.0);
uniform vec3 precomputed_sun_dir = vec3(1.0, 0.0, 0.0);
uniform vec3 precomputed_sun_color : source_color = vec3(1.0);
uniform vec3 precomputed_Atmosphere_sun : source_color = vec3(0.0);
uniform vec3 precomputed_Atmosphere_ambient : source_color = vec3(0.0);
uniform vec3 precomputed_Atmosphere_ground : source_color = vec3(0.0);
uniform float precomputed_sun_size
	: hint_range(0, 90.0) = 9.250245035569947e-03;
uniform float precomputed_sun_energy = 1.0;
uniform float precomputed_background_intensity = 1.0;

// Rayleigh scattering gives the sky its blue color, its effects are visible across the whole sky
uniform vec3 rayleigh_color = vec3(0.258928571428571, 0.580357142857143, 1.0);
uniform float rayleigh
	: hint_range(0, 64) =
		  1.0; // higher values absorb more rayleigh_color, more blue by default

// Mie scattering creates a haze, which is visible around the sun and the horizon
uniform vec3 mie_color = vec3(1.0, 1.0, 1.0);
uniform float mie
	: hint_range(0, 64) = 1.0; // increase for a "foggy" atmosphere
uniform float mie_eccentricity : hint_range(-1, 0.99999) = 0.76;

// Sample counts for different parts of the sky
uniform int atmosphere_samples_max =
	32; // maximum allowed atmosphere samples per pixel
uniform int atmosphere_samples_min =
	12; // minimum allowed atmosphere samples per pixel
uniform float atmosphere_samples_horizon_bias =
	0.5; // lower values bias more samples towards the horizon
uniform int atmosphere_sun_samples =
	32; // extra samples around sun, does not exceed maximum
uniform int atmosphere_light_samples =
	8; // scattering samples from each direction towards the sun

uniform float turbidity : hint_range(0, 1000) = 1.0;
uniform vec3 ground_color : source_color = vec3(0.1, 0.07, 0.034);

// Brightness controls
uniform float intensity = 10.0; // Intensity of sky. Does not affect clouds
uniform float sun_brightness = 10000.0; // brightness of only the solar disk
uniform float ground_brightness = 1.0;
uniform float night_sky_brightness = 1000.0;

// Night sky texture
uniform sampler2D night_sky : source_color, hint_default_black;

uniform sampler2D ground_texture : source_color, hint_default_white;
uniform vec3 ground_rotation = vec3(0.0);

uniform vec3 moon_eclipse_color : source_color = vec3(1.0, 0.1, 0.0);
uniform float moon_size_mult = 1.0;
uniform sampler2D moon_texture : source_color, hint_default_black;

// Height of viewer above the atmosphere, in addition to the camera's y
// position. Does not affect cloud height
uniform float Height = 1000.0;

uniform float earthRadius = 6360e3;
uniform float moonRadius = 1738e3;
uniform float moonDistance = 384400e3;
uniform float atmosphereRadius = 6420e3;
uniform float rayleighScaleHeight =
	7994.0;							   // Scale height for Rayleigh scattering
uniform float mieScaleHeight = 1200.0; // Scale height for Mie scattering

const float BetaRScale = 22.4e-6;
const float BetaMScale = 20e-6;
// const vec3 BetaR = vec3(5.8e-6,13.0e-6,22.4e-6);
// const vec3 BetaM = vec3(20e-6);

// dir is normalized
vec3 solve_quadratic(vec3 origin, vec3 dir, float Radius) {
	float b = 2.0 * dot(dir, origin);
	float c = dot(origin, origin) - Radius * Radius;
	float d = b * b - 4.0 * c;
	float dsqrt = sqrt(d);
	float x1 = (-b + dsqrt) * 0.5;
	float x2 = (-b - dsqrt) * 0.5;
	return vec3(x1, x2, d);
}

vec3[5] atmosphere(vec3 dir, vec3 pos) {
	vec3 SunDirection = precomputed_sun_dir;
	vec3 start = vec3(0.0);
	vec3 end = vec3(0.0);

	vec3 cameraPos = vec3(0, earthRadius + Height + max(0.0, pos.y), 0);
	start = cameraPos;

	vec3 d1 = solve_quadratic(cameraPos, dir, atmosphereRadius);
	// Find atmosphere end point, exit if no intersection
	if (d1.x > d1.y && d1.x > 0.0) {
		end = cameraPos + dir * d1.x;

		// If the ray starts outside the atmosphere, set the origin to the edge
		// of the atmosphere
		if (d1.y > 0.0) {
			start = cameraPos + dir * d1.y;
		}
	} else {
		return {vec3(0.0), vec3(1.0), vec3(0.0), vec3(1.0), end};
	}

	float ground = 0.0;
	// Check if ray intersects with ground, and set the end point to the ground
	// if it intersects
	vec3 d2 = solve_quadratic(cameraPos, dir, earthRadius);
	if (d2.x > 0.0 && d2.y > 0.0) {
		end = cameraPos + dir * d2.y;
		ground = 1.0; // enable ground
		//end = cameraPos + dir * d1.y; // optionally disable ground, buggy at high altitudes and low sample counts, set a higher height instead.
		//return {vec3(0.0), vec3(1.0), vec3(1.0), vec3(1.0), end}; // optionally disable atmosphere lighting, must set ground brightness to 0 as well.
	}

	vec3 SumR = vec3(0.0);
	vec3 SumM = vec3(0.0);
	float mu = dot(dir, SunDirection);
	float phaseR = (3.0 / (16.0 * PI)) * (1.0 + mu * mu);
	float phaseM =
		(3.0 / (8.0 * PI)) *
		((1.0 - mie_eccentricity * mie_eccentricity) * (1.0 + mu * mu) /
		 ((2.0 + mie_eccentricity * mie_eccentricity) *
		  pow(1.0 + mie_eccentricity * mie_eccentricity -
				  2.0 * mie_eccentricity * mu,
			  1.5)));

	float segmentLength = distance(start, end);
	float horizon = sin(acos(earthRadius / (earthRadius + Height)));

	// Bias atmosphere samples towards sun and horizon
	float weighted_atmosphere_samples = ceil(
		clamp((max(clamp(1.0 - pow(abs(dir.y + horizon),
								   atmosphere_samples_horizon_bias),
						 0.0, 1.0) *
					   float(atmosphere_samples_max),
				   pow(max(mu, 0.0), 3.0) * float(atmosphere_sun_samples))),
			  float(atmosphere_samples_min), float(atmosphere_samples_max)));

	segmentLength /= weighted_atmosphere_samples;

	float opticalDepthR = 0.0;
	float opticalDepthM = 0.0;

	vec3 atmosphere_atten = vec3(0.0);
	vec3 BetaR = rayleigh_color * BetaRScale * rayleigh;
	vec3 BetaM = mie_color * BetaMScale * mie;

	for (float i = 0.5; i < weighted_atmosphere_samples + 0.5; i++) {
		vec3 Px = start + dir * segmentLength * i;
		float sampleHeight = length(Px) - earthRadius;

		float Hr_sample =
			exp(-sampleHeight / (rayleighScaleHeight * turbidity)) *
			segmentLength;
		float Hm_sample =
			exp(-sampleHeight / (mieScaleHeight * turbidity)) * segmentLength;

		opticalDepthR += Hr_sample;
		opticalDepthM += Hm_sample;

		if (precomputed_sun_enabled < 0.5)
			continue;

		float opticalDepthLR = 0.0;
		float opticalDepthLM = 0.0;

		vec3 d3 = solve_quadratic(Px, SunDirection, atmosphereRadius);
		vec3 d4 = solve_quadratic(Px, SunDirection, earthRadius);

		// Ignore sample if sun is below horizon, used for performance boost at
		// night time. Also fixes spots at edges at high altitudes
		if ((d4.x > 0.0 && d4.y > 0.0) || d3.z < 0.0)
			continue;

		float segmentLengthL =
			max(d3.x, d3.y) / float(atmosphere_light_samples);

		int j2 = 0;
		for (float j = 0.5; j < float(atmosphere_light_samples) + 0.5; j++) {
			float sampleHeightL =
				length(Px + SunDirection * segmentLengthL * j) - earthRadius;

			// Ignore light samples inside planet, used for performance boost at
			// night time
			if (sampleHeightL < 0.0)
				break;
			opticalDepthLR +=
				exp(-sampleHeightL / (rayleighScaleHeight * turbidity));
			opticalDepthLM +=
				exp(-sampleHeightL / (mieScaleHeight * turbidity));
			j2++;
		}

		// Attenuation
		if (j2 == atmosphere_light_samples) {
			opticalDepthLR *= segmentLengthL;
			opticalDepthLM *= segmentLengthL;
			vec3 tau = BetaR * (opticalDepthR + opticalDepthLR) +
					   BetaM * 1.1 * (opticalDepthM + opticalDepthLM);
			vec3 attenuation = exp(-tau);

			atmosphere_atten += attenuation;
			SumR += Hr_sample * attenuation;
			SumM += Hm_sample * attenuation;
		}
	}

	vec3 Sky = SumR * phaseR * BetaR + SumM * phaseM * BetaM;
	return {Sky, atmosphere_atten, vec3(ground),
			exp(-(opticalDepthR * BetaR + opticalDepthM * BetaM)), end};
}

vec3 rotate(vec3 point, vec3 axis, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	float oc = 1.0 - c;

	vec3 rotatedPoint;
	rotatedPoint.x = point.x * (oc * axis.x * axis.x + c) +
					 point.y * (oc * axis.x * axis.y - axis.z * s) +
					 point.z * (oc * axis.x * axis.z + axis.y * s);
	rotatedPoint.y = point.x * (oc * axis.x * axis.y + axis.z * s) +
					 point.y * (oc * axis.y * axis.y + c) +
					 point.z * (oc * axis.y * axis.z - axis.x * s);
	rotatedPoint.z = point.x * (oc * axis.x * axis.z - axis.y * s) +
					 point.y * (oc * axis.y * axis.z + axis.x * s) +
					 point.z * (oc * axis.z * axis.z + c);

	return rotatedPoint;
}

vec2 sphereToUV(vec3 point, vec3 rot) {
	point = rotate(rotate(point, vec3(1.0, 0.0, 0.0), rot.x),
				   vec3(0.0, 1.0, 0.0), rot.y);
	float theta = atan(point.x, point.y);
	float phi = acos(-point.z / length(point));

	vec2 uv = vec2((theta - (rot.z - 1.0)) * 0.5, // Rotate U
				   phi) /
			  PI;

	return uv;
}

vec3 uvToSphere(vec2 uv) {
	float theta = (1.0 - uv.x) * PI;
	float phi = uv.y * TAU;
	return vec3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));
}

vec3 map_sphere_normal(vec3 x, vec3 y, vec3 z, vec2 point) {
	return x * point.x + y * point.y +
		   z * sqrt(1.0 - point.x * point.x - point.y * point.y);
}

vec4[4] sample_sky(vec3 dir, vec3 pos, float visiblity) {
	vec3[5] sky = atmosphere(dir, pos);

	vec3 d2 =
		solve_quadratic(vec3(0, earthRadius + Height + max(0.0, POSITION.y), 0),
						dir, earthRadius);
	vec3 end = sky[4] / earthRadius * 2.0;
	vec2 uv =
		sphereToUV(rotate(rotate(end, vec3(0.0, 0.0, 1.0),
								 pos.x * PI / (earthRadius + pos.y + Height)),
						  vec3(1.0, 0.0, 0.0),
						  pos.z * PI / (earthRadius + pos.y + Height)),
				   ground_rotation * 0.5);

	// Sun, with sun-specific attenuation
	vec3 sun = (vec3(1.0) - exp(-sky[1])) *
			   max(max(dot(dir, precomputed_sun_dir), 0.0) -
					   (cos(precomputed_sun_size)),
				   0.0) *
			   sun_brightness * (1.0 - sky[2].r) * visiblity * precomputed_sun_energy;

	// ground, with generic attenuation
	vec3 ground = (vec3(1.0) - exp(-sky[3])) * ground_color *
				  texture(ground_texture, uv).xyz * sky[2].r *
				  ground_brightness;
	ground *= clamp(dot(end, precomputed_sun_dir), 0.0, 1.0);
	vec3 col = (ground + sky[0].xyz) * precomputed_sun_energy;
	return {vec4(col * precomputed_sun_color, sky[2].r),
			vec4(sky[3] * (1.0 - sky[2].r), 1.0), vec4(sun, 1.0),
			vec4(end, 0.0)};
}

/* Begin Cloud Parameters */

// Cloud Raymarching based on: A. Schneider. “The earthRadiusal-Time Volumetric
// Cloudscapes Of Horizon: Zero Dawn”. ACM SIGGRAPH. Los Angeles, CA: ACM
// SIGGRAPH, 2015. Web. 26 Aug. 2015.

uniform sampler3D worlnoise : filter_linear_mipmap, repeat_enable;
uniform sampler3D perlworlnoise : filter_linear_mipmap, repeat_enable;
uniform sampler2D weathermap : filter_linear_mipmap, repeat_enable;

uniform bool clouds = true;
uniform int cloud_samples_horizon = 54;
uniform int cloud_samples_sky = 96;
uniform float _density : hint_range(0.01, 0.5) = 0.097;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.25;
uniform float _time_scale : hint_range(0.0, 20.0) = 1.0;
uniform float _time_offset = 0.0;

uniform float cloud_bottom = 1500.0;
uniform float cloud_top = 4000.0;
uniform float cloud_brightness = 1.0;
uniform float cloud_ambient_brightness = 0.5;

// From: https://www.shadertoy.com/view/4sfGzS credit to iq
float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Utility function that maps a value from one range to another.
float remap(float originalValue, float originalMin, float originalMax,
			float newMin, float newMax) {
	return newMin +
		   (((originalValue - originalMin) / (originalMax - originalMin)) *
			(newMax - newMin));
}

// Phase function
float henyey_greenstein(float cos_theta, float G) {
	const float k = 0.0795774715459;
	return k * (1.0 - G * G) / (pow(1.0 + G * G - 2.0 * G * cos_theta, 1.5));
}

float GetHeightFractionForPoint(float inPosition) {
	float height_fraction =
		(inPosition - cloud_bottom - earthRadius) / (cloud_top - cloud_bottom);
	return clamp(height_fraction, 0.0, 1.0);
}

vec4 mixGradients(float cloudType) {
	const vec4 STRATUS_GRADIENT = vec4(0.02f, 0.05f, 0.09f, 0.11f);
	const vec4 STRATOCUMULUS_GRADIENT = vec4(0.02f, 0.2f, 0.48f, 0.625f);
	const vec4 CUMULUS_GRADIENT = vec4(0.01f, 0.0625f, 0.78f, 1.0f);
	float stratus = 1.0f - clamp(cloudType * 2.0f, 0.0, 1.0);
	float stratocumulus = 1.0f - abs(cloudType - 0.5f) * 2.0f;
	float cumulus = clamp(cloudType - 0.5f, 0.0, 1.0) * 2.0f;
	return STRATUS_GRADIENT * stratus + STRATOCUMULUS_GRADIENT * stratocumulus +
		   CUMULUS_GRADIENT * cumulus;
}

float densityHeightGradient(float heightFrac, float cloudType) {
	vec4 cloudGradient = mixGradients(cloudType);
	return smoothstep(cloudGradient.x, cloudGradient.y, heightFrac) -
		   smoothstep(cloudGradient.z, cloudGradient.w, heightFrac);
}

// Returns density at a given point
// Heavily based on method from Schneider
float density(vec3 pip, vec3 weather, float mip) {
	float time = mod(TIME, 100.0);
	vec3 p = pip;
	p.x += time * 1.0 * _time_scale + _time_offset;
	float height_fraction = GetHeightFractionForPoint(length(p));
	vec4 n = textureLod(perlworlnoise, p.xyz * 0.00008, mip - 2.0);
	float fbm = n.g * 0.625 + n.b * 0.25 + n.a * 0.125;
	float G = densityHeightGradient(height_fraction, weather.r);
	float base_cloud = remap(n.r, -(1.0 - fbm), 1.0, 0.0, 1.0);
	float weather_coverage = cloud_coverage * weather.b;
	base_cloud = remap(base_cloud * G, 1.0 - (weather_coverage), 1.0, 0.0, 1.0);
	base_cloud *= weather_coverage;
	p.xy -= time * 4.0 * _time_scale + _time_offset;
	vec3 hn = textureLod(worlnoise, p * 0.001, mip).rgb;
	float hfbm = hn.r * 0.625 + hn.g * 0.25 + hn.b * 0.125;
	hfbm = mix(hfbm, 1.0 - hfbm, clamp(height_fraction * 4.0, 0.0, 1.0));
	base_cloud = remap(base_cloud, hfbm * 0.4 * height_fraction, 1.0, 0.0, 1.0);
	return pow(clamp(base_cloud, 0.0, 1.0),
			   (1.0 - height_fraction) * 0.8 + 0.5);
}

vec4 march(vec3 pos, vec3 end, vec3 dir, int depth, float sun_visible,
		   float true_density) {
	const vec3 RANDOM_VECTORS[6] = {
		vec3(0.38051305f, 0.92453449f, -0.02111345f),
		vec3(-0.50625799f, -0.03590792f, -0.86163418f),
		vec3(-0.32509218f, -0.94557439f, 0.01428793f),
		vec3(0.09026238f, -0.27376545f, 0.95755165f),
		vec3(0.28128598f, 0.42443639f, -0.86065785f),
		vec3(-0.16852403f, 0.14748697f, 0.97460106f)};
	float T = 1.0;
	float alpha = 0.0;
	vec3 ldir = precomputed_sun_dir;
	float ss = length(dir);
	dir = dir / ss;
	vec3 p = pos + hash(pos * 10.0) * ss;
	float t_dist = cloud_top - cloud_bottom;
	float lss = (t_dist / 36.0);
	vec3 L = vec3(0.0);
	float t = 1.0;
	float costheta = dot(ldir, dir);
	// Stack multiple phase functions to emulate some backscattering
	float phase = max(max(henyey_greenstein(costheta, 0.6),
						  henyey_greenstein(costheta, (0.4 - 1.4 * ldir.y))),
					  henyey_greenstein(costheta, -0.2));
	vec3 atmosphere_sun = precomputed_Atmosphere_sun * ss * cloud_brightness *
						  precomputed_sun_energy * phase;
	vec3 atmosphere_ambient =
		precomputed_Atmosphere_ambient * cloud_ambient_brightness * intensity;
	vec3 atmosphere_ground = precomputed_Atmosphere_ground * ground_color.xyz *
							 ground_brightness * precomputed_sun_energy *
							 intensity;

	const float weather_scale = 0.00006;
	float time = mod(TIME, 10000.0) * 0.0003 * _time_scale + 0.005 * _time_offset;
	vec2 weather_pos = vec2(time * 0.9, time);

	for (int i = 0; i < depth; i++) {
		p += dir * ss;
		vec3 weather_sample =
			texture(weathermap, p.xz * weather_scale + 0.5 + weather_pos).xyz;
		float height_fraction = GetHeightFractionForPoint(length(p));

		t = density(p, weather_sample, 0.0);
		float dt = exp(-true_density * t * ss);
		T *= dt;
		vec3 lp = p;
		float lt = 1.0;
		float cd = 0.0;

		if (t > 0.0) { // calculate lighting, but only when we are in the cloud
			for (float j = 0.0; j < 6.0 * sun_visible; j++) {
				lp += (ldir + RANDOM_VECTORS[int(j)] * j) * lss;
				vec3 lweather = texture(weathermap, lp.xz * weather_scale +
														0.5 + weather_pos)
									.xyz;
				lt = density(lp, lweather, j);
				cd += lt;
			}

			// Take a single distant sample
			lp = p + ldir * 18.0 * lss;
			float lheight_fraction = GetHeightFractionForPoint(length(lp));
			vec3 lweather =
				texture(weathermap, lp.xz * weather_scale + 0.5).xyz;
			lt = pow(density(lp, lweather, 5.0),
					 (1.0 - lheight_fraction) * 0.8 + 0.5);
			cd += lt;

			// captures the direct lighting from the sun
			float beers = exp(-true_density * cd * lss);
			float beers2 = exp(-true_density * cd * lss * 0.25) * 0.7;
			float beers_total = max(beers, beers2);

			vec3 ambient = mix(atmosphere_ground, atmosphere_ambient,
							   smoothstep(0.0, 1.0, height_fraction)) *
						   beers;
			//			vec3 ambient = mix(atmosphere_ground, vec3(1.0),
			//smoothstep(0.0, 1.0, height_fraction)) * true_density *
			//mix(atmosphere_ambient, vec3(1.0), 0.4); // * (ldir .y);
			alpha += (1.0 - dt) * (1.0 - alpha);
			L += ((ambient + beers_total * atmosphere_sun) * alpha) * T * t;
		}
	}
	return vec4(L * cloud_brightness, clamp(alpha, 0.0, 1.0));
}

/* End Cloud Parameters */

void sky() {
	vec3 dir = EYEDIR;

	float sun_visible =
		precomputed_sun_visible *
		max(sign(precomputed_sun_dir.y +
				 sin(acos(earthRadius / (earthRadius + cloud_top)) +
					 precomputed_sun_size)),
			0.0);
	vec4 cloud_col = vec4(0.0);
	float cloud_fade_stars = 1.0;
	float cloud_fade = 1.0;
	bool AT_FULL_RES_PASS = !(AT_HALF_RES_PASS || AT_QUARTER_RES_PASS);
	float horizon =
		sin(acos(earthRadius / (earthRadius + max(POSITION.y, 0.0) + Height)));
	float horizon_dist = dir.y + horizon;

	if (clouds) {
		/* start Clouds */
		//		if (POSITION.y < cloud_top){
		if ((AT_CUBEMAP_PASS && AT_QUARTER_RES_PASS) ||
			(!AT_CUBEMAP_PASS && AT_HALF_RES_PASS)) {
			float true_density =
				_density * pow(1.0 - clamp((POSITION.y - cloud_bottom) /
											   (cloud_top - cloud_bottom),
										   0.0, 1.0),
							   2.0);
			vec4 volume = vec4(0.0);

			if (horizon_dist > 0.0 && true_density > 0.0) {
				vec3 camPos =
					vec3(POSITION.x, min(POSITION.y, cloud_bottom) + earthRadius, POSITION.z);
				vec3 d1 = solve_quadratic(camPos, dir, cloud_top + earthRadius);
				vec3 d2 =
					solve_quadratic(camPos, dir, cloud_bottom + earthRadius);
				float cloud_start_distance = d2.x;
				float cloud_end_distance = d1.x;
				vec3 start = camPos + dir * cloud_start_distance;
				vec3 end = camPos + dir * cloud_end_distance;

				/*// Find atmosphere end point, exit if no intersection
				if (d1.x > d1.y && d1.x > 0.0){
					end = camPos + dir * d1.x;

					// If the ray starts outside the atmosphere, set the origin
				to the edge of the atmosphere if (d1.y > 0.0){ start = camPos +
				dir * d1.y;
					}
				}*/

				float shelldist = (cloud_end_distance - cloud_start_distance);

				// Take more steps towards horizon, less steps in foggy clouds,
				// and less steps at night
				float steps = ceil(mix(
					float(cloud_samples_horizon) *
						(1.0 -
						 0.25 * (1.0 - sun_visible * (1.0 - cloud_coverage))),
					float(cloud_samples_sky) *
						(1.0 - 0.25 * (1.0 - sun_visible)),
					sqrt(clamp(dir.y + horizon, 0.0, 1.0))));
				vec3 raystep = dir * shelldist / steps;
				volume = march(start, end, raystep, int(steps),
							   precomputed_sun_visible, true_density);
				volume.xyz *= precomputed_sun_visible * precomputed_sun_color;
			}
			COLOR = volume.xyz;
			ALPHA = clamp(volume.w, 0.0, 1.0);
		} else if (AT_FULL_RES_PASS) {
			cloud_fade = clamp(dir.y, 0.0, 1.0);
			cloud_fade_stars = clamp(horizon_dist, 0.0, 1.0);
			cloud_col = AT_CUBEMAP_PASS ? QUARTER_RES_COLOR : HALF_RES_COLOR;
		}
		//		}
		/* End Clouds */
	}

	float moon_size =
		(moonRadius /
		 length((moonDistance + earthRadius) * precomputed_moon_dir[2] -
				vec3(0.0, POSITION.y + earthRadius + Height, 0.0)) *
		 2.0) *
		moon_size_mult;

	float sun_visibility = 1.0 - clamp((dot(EYEDIR, precomputed_moon_dir[2]) -
										sqrt(1.0 - 0.25 * (moon_size / 45.0))) *
										   100000.0,
									   0.0, 1.0);

	if (AT_FULL_RES_PASS) {
		vec4[4] background = sample_sky(dir, POSITION, sun_visibility);
		vec4 col_moon = vec4(vec3(0.0), 0.0);
		vec2 moon_cord = vec2(dot(EYEDIR, precomputed_moon_dir[1]),
							  dot(EYEDIR, precomputed_moon_dir[0])) /
						 sqrt(moon_size / 45.0);

		vec3 moon_to_sun = precomputed_sun_dir;
		if (dot(EYEDIR, precomputed_moon_dir[2]) >
			sqrt(1.0 - 0.25 * (moon_size / 45.0))) {
			vec3 moon_normal = normalize(map_sphere_normal(
				precomputed_moon_dir[1], precomputed_moon_dir[0],
				-precomputed_moon_dir[2] * 0.5, moon_cord * 2.0));
			float earth_shadow_sharpness = 200.0;
			col_moon = texture(moon_texture, vec2(0.5) - moon_cord.yx);
			float moon_dist_earth_ratio =
				1.0 - atan(earthRadius / (moonDistance + earthRadius)) / TAU;
			float moon_eclipse = (clamp((moon_dist_earth_ratio -
						max(dot(-normalize(
									precomputed_moon_dir[2] *
										(earthRadius + moonDistance) +
									vec3(0.0, POSITION.y + earthRadius + Height,
										 0.0)),
								normalize(precomputed_sun_dir)),
							0.0)) /
						   moon_dist_earth_ratio * earth_shadow_sharpness,
					   0.0, 1.0));

			col_moon.xyz *= precomputed_background_intensity *
				precomputed_sun_energy *
				(clamp(dot(moon_normal, moon_to_sun), 0.0, 1.0)) * moon_eclipse * mix(moon_eclipse_color, vec3(1.0), moon_eclipse)
				;
		}
		vec3 col_stars =
			(texture(night_sky,
					 sphereToUV(EYEDIR,
								vec3(PI * 0.5 + POSITION.z * PI /
													(earthRadius + POSITION.y +
													 Height),
									 -POSITION.x * PI /
										 (earthRadius + POSITION.y + Height),
									 -PI * 0.5) +
									ground_rotation * 0.5))
					 .xyz *
				 night_sky_brightness * (1.0 - col_moon.w) +
			 col_moon.xyz * col_moon.w) *
			background[1].xyz / precomputed_background_intensity;

		cloud_col.a = clamp(cloud_col.a*precomputed_background_intensity/sun_brightness, 0.0, 1.0);
		float cloud_passthrough = (1.0 - cloud_col.a) * cloud_fade_stars;

		// Eclipse needs reworking
		float sun_passthrough = 1.0;
		if (moon_size > 0.0) {
			float sun_atten_range = sin(precomputed_sun_size);
			float moon_atten_range = sin(radians(moon_size)) * 0.5;
			sun_passthrough =
				pow(clamp(1.0 - clamp(min(dot(precomputed_moon_dir[2],
											  precomputed_sun_dir),
										  1.0) -
										  (1.0 - moon_atten_range),
									  0.0, 1.0) /
									moon_atten_range,
						  0.0, 1.0),
					2.0);
			// sun_passthrough =
			// sqrt(mix(clamp(sin(precomputed_sun_size)-sin(radians(moon_size)),
			// 0.0, 1.0), 1.0, sun_passthrough));
		}
		// Eclipse needs reworking

		//		float moon_tint_ratio
		//= 1.0-atan(moonRadius/(moonDistance+earthRadius))/TAU; 		sun_passthrough
		//= 1.0-clamp((dot(normalize(normalize(map_sphere_normal(vec3(1.0, 0.0,
		//0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0)*0.5,
		//background[3].xz*0.5)))
		//		*earthRadius+precomputed_moon_dir[2]*(moonDistance+earthRadius),
		//precomputed_sun_dir)-moon_tint_ratio)/(1.0-moon_tint_ratio)*10.0,0.0,1.0);
		//		COLOR = vec3(clamp(
		//			clamp(dot(normalize(normalize(
		//			map_sphere_normal(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0),
		//vec3(0.0, 0.0, 1.0)*0.5, background[3].xz*2.0))*earthRadius
		//			-precomputed_moon_dir[2]*(moonDistance+earthRadius)),
		//			precomputed_sun_dir)+moon_tint_ratio, 0.0, 1.0)*100000.0
		//			, 0.0, 1.0));
		//		COLOR = vec3(clamp(dot(normalize(normalize(
		//			-map_sphere_normal(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0),
		//vec3(0.0, 0.0, 1.0), background[3].xz*0.5))*earthRadius
		//			+precomputed_moon_dir[2]*(moonDistance+earthRadius)),
		//			-precomputed_sun_dir)+moon_tint_ratio,
		//0.0, 1.0)/(1.0-moon_tint_ratio));

		vec3 sky_col = background[0].xyz * intensity *
					(max(precomputed_sun_dir.y,
						 clamp((POSITION.y + Height) /
								   (atmosphereRadius - earthRadius),
							   0.0, 1.0))) *
					precomputed_sun_enabled * sun_passthrough;
		sky_col =
			mix(sky_col,
				vec3(sky_col.x + sky_col.y + sky_col.z) * 0.0033333333,
				pow(clamp((cloud_coverage - 0.25) / 0.75, 0.0, 1.0), 0.5));
		cloud_col.xyz *= sun_passthrough;
		vec3 sun_col = background[2].xyz * intensity * precomputed_sun_enabled;
		// clamp(vec3(0.3)-clamp(cloud_col.www*cloud_fade_stars, 0.0, 1.0),
		// 0.0, 1.0)
		COLOR = sky_col
			+ sun_col * (1.0 - cloud_col.w)
			+ cloud_col.xyz * cloud_fade_stars * mix(cloud_fade_stars, 1.0, clamp(precomputed_sun_dir.y, 0.0, 1.0))
			+ col_stars * (1.0 - cloud_col.w);
	}
}
