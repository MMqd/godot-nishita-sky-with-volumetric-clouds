shader_type sky;
render_mode use_debanding;
render_mode use_half_res_pass;

//These properties are precomputed by the NishitaSky script, and cannot be modified
uniform float precomputed_sun_enabled = 1.0;
uniform vec3 precomputed_sun_dir = vec3(1.0, 0.0, 0.0);
uniform vec3 precomputed_sun_color : source_color = vec3(1.0);
uniform vec3 precomputed_Atmosphere_sun : source_color = vec3(0.0);
uniform vec3 precomputed_Atmosphere_ambient : source_color = vec3(0.0);
uniform vec3 precomputed_Atmosphere_ground : source_color = vec3(0.0);

//Controls the scattering responsible for the blue color of a real life sky
uniform vec3 rayleigh_color = vec3(0.258928571428571, 0.580357142857143, 1.0);
uniform float rayleigh : hint_range(0, 64) = 1.0; // higher values absorb more rayleigh_color, more blue by default

//Controls the scattering responsible for the white horizon of a real life sky
uniform vec3 mie_color = vec3(1.0, 1.0, 1.0);
uniform float mie : hint_range(0, 64) = 1.0; // higher values make a "foggy" atmosphere
uniform float mie_eccentricity : hint_range(-1, 0.99999) = 0.76;

//Sample counts for different parts of the sky
uniform int atmosphere_samples_max = 32; //maximum allowed atmosphere samples per pixel
uniform int atmosphere_samples_min = 12; //minimum allowed atmosphere samples per pixel
uniform int atmosphere_sun_samples = 32; //extra samples around sun, does not exceed maximum
uniform int atmosphere_light_samples = 8; //scattering samples from each direction towards the sun

uniform float turbidity : hint_range(0, 1000) = 1.0;
uniform vec3 ground_color : source_color = vec3(0.1, 0.07, 0.034);

//Brightness controls
uniform float intensity = 10.0; //Intensity of sky. Does not affect clouds
uniform float sun_brightness = 100000.0; //brightness of only the solar disk
uniform float ground_brightness = 0.5;
uniform float night_sky_brightness = 0.001;

//Night sky texture
uniform sampler2D night_sky : source_color, hint_default_black;

//Height of viewer above the atmosphere, in addition to the camera's y position. Does not affect cloud height
uniform float Height = 1000.0;

uniform float earthRadius = 6360e3;
uniform float atmosphereRadius = 6420e3;
uniform float rayleighScaleHeight = 7994.0; // Scale height for Rayleigh scattering
uniform float mieScaleHeight = 1200.0; // Scale height for Mie scattering

const float BetaRScale = 22.4e-6;
const float BetaMScale = 20e-6;
//const vec3 BetaR = vec3(5.8e-6,13.0e-6,22.4e-6);
//const vec3 BetaM = vec3(20e-6);

//dir is normalized
vec3 solve_quadratic(vec3 origin, vec3 dir, float Radius){
	float b = 2.0 * dot(dir, origin);
	float c = dot(origin, origin) - Radius * Radius;
	float d = b*b - 4.0 * c;
	float dsqrt = sqrt(d);
	float x1 = (-b + dsqrt) * 0.5;
	float x2 = (-b - dsqrt) * 0.5;
	return vec3(x1, x2, d);
}

vec3[4] atmosphere(vec3 dir, vec3 pos){
	vec3 SunDirection = precomputed_sun_dir;
	vec3 begin = vec3(0.0);
	vec3 end = vec3(0.0);

	vec3 cameraPos = vec3(0,earthRadius + Height + max(0.0, pos.y),0);
	begin = cameraPos;

	vec3 d1 = solve_quadratic(cameraPos, dir, atmosphereRadius);
	// Find atmosphere end point, exit if no intersection
    if (d1.x > d1.y && d1.x > 0.0){
		end = cameraPos + dir * d1.x;

		// If the ray starts outside the atmosphere, set the origin to the edge of the atmosphere
		if (d1.y > 0.0){
			begin = cameraPos + dir * d1.y;
		}
	} else {
		return {vec3(0.0), vec3(1.0), vec3(0.0), vec3(1.0) };
	}

	float ground = 0.0;
	// Check if ray intersects with ground, and set the end point to the ground if it intersects
	vec3 d2 = solve_quadratic(cameraPos, dir, earthRadius);
    if (d2.x > 0.0 && d2.y > 0.0){
		end = cameraPos + dir * d2.y;
//		end = cameraPos + dir * d1.y; //optionally disable earth, must set ground brightness to 0 as well. Increase height instead to hide ground.
		ground=1.0;
	}

	vec3 SumR = vec3(0.0);
	vec3 SumM = vec3(0.0);
	float mu = dot(dir, SunDirection);
	float phaseR = (3.0 / (16.0 * PI)) * (1.0 + mu * mu);
	float phaseM = (3.0 / (8.0 * PI)) * ((1.0 - mie_eccentricity*mie_eccentricity) * (1.0 + mu * mu) / ((2.0 + mie_eccentricity * mie_eccentricity) * pow(1.0 + mie_eccentricity * mie_eccentricity - 2.0 * mie_eccentricity * mu, 1.5)));

	float segmentLength = distance (begin, end);
	float horizon = sin(acos(earthRadius / (earthRadius + Height)));

	// Bias atmosphere samples away from the sun, and towards the horizon
	float weighted_atmosphere_samples = ceil(clamp(
		(clamp(1.0 - pow(abs(dir.y + horizon), 0.5), 0.0, 1.0)
		* float(atmosphere_samples_max) 
		+ pow(max(mu, 0.0), 2.0) * float(atmosphere_sun_samples)
		), float(atmosphere_samples_min), float(atmosphere_samples_max)));

	segmentLength /= weighted_atmosphere_samples;

	float opticalDepthR = 0.0;
  	float opticalDepthM = 0.0;

	vec3 atmosphere_atten = vec3(0.0);
		vec3 BetaR = rayleigh_color * BetaRScale * rayleigh;
		vec3 BetaM = mie_color * BetaMScale * mie;

	for (float i = 0.5; i < weighted_atmosphere_samples + 0.5; i++) {
		vec3 Px = begin + dir * segmentLength * i;
		float sampleHeight = length(Px) - earthRadius;

		float Hr_sample = exp(-sampleHeight / (rayleighScaleHeight * turbidity)) * segmentLength;
		float Hm_sample = exp(-sampleHeight / (mieScaleHeight * turbidity)) * segmentLength;

		opticalDepthR += Hr_sample;
		opticalDepthM += Hm_sample;

		float opticalDepthLR = 0.0;
		float opticalDepthLM = 0.0;

		vec3 d3 = solve_quadratic(Px, SunDirection, atmosphereRadius);
		vec3 d4 = solve_quadratic(Px, SunDirection, earthRadius);

		// Ignore sample if sun is below horizon, used for performance boost at night time
		if (d4.x > 0.0 && d4.y > 0.0)
			continue;

		float segmentLengthL = max(d3.x, d3.y) / float(atmosphere_light_samples);

		int j2 = 0;
		for (float j = 0.5; j < float(atmosphere_light_samples) + 0.5; j++) {
			float sampleHeightL = length(Px + SunDirection * segmentLengthL * j) - earthRadius;

			// Ignore light samples inside planet, used for performance boost at night time
			if (sampleHeightL < 0.0)
				break;
			opticalDepthLR += exp(-sampleHeightL/(rayleighScaleHeight*turbidity));
			opticalDepthLM += exp(-sampleHeightL/(mieScaleHeight*turbidity));
			j2++;
		}

		// Attenuation
		if (j2 == atmosphere_light_samples){
			opticalDepthLR *= segmentLengthL;
			opticalDepthLM *= segmentLengthL;
			vec3 tau = BetaR * (opticalDepthR + opticalDepthLR) + BetaM * 1.1 * (opticalDepthM + opticalDepthLM);
			vec3 attenuation = exp(-tau);

			atmosphere_atten += attenuation;
			SumR += Hr_sample * attenuation;
			SumM += Hm_sample * attenuation;
		}
	}
	
	vec3 Sky = SumR * phaseR * BetaR  +  SumM * phaseM * BetaM;
	return {Sky, atmosphere_atten, vec3(ground), exp(-(opticalDepthR * BetaR + opticalDepthM * BetaM)) };
}

vec4[2] sample_sky(vec3 dir, vec3 pos){
	vec3[4] sky = atmosphere(dir, pos);
	vec3 sun = vec3(0.0);
	sun =
		// Sun, with sun-specific attenuation
	 ( (vec3(1.0)-exp(-sky[1])) * max(max(dot(dir, precomputed_sun_dir), 0.0) - (cos(LIGHT0_SIZE * 0.5)), 0.0) * sun_brightness * (1.0 - sky[2].r) + 

		// ground, with generic attenuation
	  (vec3(1.0)-exp(-sky[3])) * ground_color * max(precomputed_sun_dir.y, 0.0) * sky[2].r * ground_brightness ) * LIGHT0_ENERGY ;
	vec3 col = (sun + sky[0].xyz);
	return {vec4(col * precomputed_sun_color, sky[2].r), vec4(sky[3] * (1.0 - sky[2].r), 1.0)};
}


/* Begin Cloud Parameters */

// Cloud Raymarching based on: A. Schneider. “The earthRadiusal-Time Volumetric Cloudscapes Of Horizon: Zero Dawn”. ACM SIGGRAPH. Los Angeles, CA: ACM SIGGRAPH, 2015. Web. 26 Aug. 2015.

uniform sampler3D worlnoise : filter_linear_mipmap, repeat_enable;
uniform sampler3D perlworlnoise : filter_linear_mipmap, repeat_enable;
uniform sampler2D weathermap : filter_linear_mipmap, repeat_enable;

uniform bool clouds = true;
uniform int cloud_samples_horizon = 96;
uniform int cloud_samples_sky = 54;
uniform float _density : hint_range(0.01, 0.5) = 0.13;
uniform float cloud_coverage :hint_range(0.0, 1.0) = 0.25;
uniform float _time_scale :hint_range(0.0, 20.0) = 1.0;
uniform float _time_offset : hint_range(0.0, 1000.0, 0.5) = 0.0;

uniform float cloud_bottom = 1500.0;
uniform float cloud_top = 4000.0;
uniform float cloud_brightness = 1.5;
uniform float cloud_ambient_brightness = 2.5;
uniform float cloud_distance_fade = 0.08;

// From: https://www.shadertoy.com/view/4sfGzS credit to iq
float hash(vec3 p) {
	p = fract( p * 0.3183099 + 0.1 );
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Utility function that maps a value from one range to another. 
float remap(float originalValue, float originalMin, float originalMax, float newMin, float newMax) {
	return newMin + (((originalValue - originalMin) / (originalMax - originalMin)) * (newMax - newMin));
}

// Phase function
float henyey_greenstein(float cos_theta, float G) {
	const float k = 0.0795774715459;
	return k * (1.0 - G * G) / (pow(1.0 + G * G - 2.0 * G * cos_theta, 1.5));
}


float GetHeightFractionForPoint(float inPosition) { 
	float height_fraction = (inPosition - cloud_bottom - earthRadius) / (cloud_top - cloud_bottom); 
	return clamp(height_fraction, 0.0, 1.0);
}

vec4 mixGradients(float cloudType){
	const vec4 STRATUS_GRADIENT = vec4(0.02f, 0.05f, 0.09f, 0.11f);
	const vec4 STRATOCUMULUS_GRADIENT = vec4(0.02f, 0.2f, 0.48f, 0.625f);
	const vec4 CUMULUS_GRADIENT = vec4(0.01f, 0.0625f, 0.78f, 1.0f);
	float stratus = 1.0f - clamp(cloudType * 2.0f, 0.0, 1.0);
	float stratocumulus = 1.0f - abs(cloudType - 0.5f) * 2.0f;
	float cumulus = clamp(cloudType - 0.5f, 0.0, 1.0) * 2.0f;
	return STRATUS_GRADIENT * stratus + STRATOCUMULUS_GRADIENT * stratocumulus + CUMULUS_GRADIENT * cumulus;
}

float densityHeightGradient(float heightFrac, float cloudType) {
	vec4 cloudGradient = mixGradients(cloudType);
	return smoothstep(cloudGradient.x, cloudGradient.y, heightFrac) - smoothstep(cloudGradient.z, cloudGradient.w, heightFrac);
}

// Returns density at a given point
// Heavily based on method from Schneider
float density(vec3 pip, vec3 weather, float mip) {
	float time = mod(TIME, 100.0);
	vec3 p = pip;
	p.x += time * 1.0 * _time_scale + _time_offset;
	float height_fraction = GetHeightFractionForPoint(length(p));
	vec4 n = textureLod(perlworlnoise, p.xyz*0.00008, mip-2.0);
	float fbm = n.g*0.625+n.b*0.25+n.a*0.125;
	float G = densityHeightGradient(height_fraction, weather.r);
	float base_cloud = remap(n.r, -(1.0-fbm), 1.0, 0.0, 1.0);
	float weather_coverage = cloud_coverage*weather.b;
	base_cloud = remap(base_cloud*G, 1.0-(weather_coverage), 1.0, 0.0, 1.0);
	base_cloud *= weather_coverage;
	p.xy -= time * 4.0 * _time_scale + _time_offset;
	vec3 hn = textureLod(worlnoise, p*0.001, mip).rgb;
	float hfbm = hn.r*0.625+hn.g*0.25+hn.b*0.125;
	hfbm = mix(hfbm, 1.0-hfbm, clamp(height_fraction*4.0, 0.0, 1.0));
	base_cloud = remap(base_cloud, hfbm*0.4 * height_fraction, 1.0, 0.0, 1.0);
	return pow(clamp(base_cloud, 0.0, 1.0), (1.0 - height_fraction) * 0.8 + 0.5);
}

vec4 march(vec3 pos, vec3 end, vec3 dir, int depth, float sun_visible) {
	const vec3 RANDOM_VECTORS[6] = {vec3( 0.38051305f, 0.92453449f, -0.02111345f),vec3(-0.50625799f, -0.03590792f, -0.86163418f),vec3(-0.32509218f, -0.94557439f,  0.01428793f),vec3( 0.09026238f, -0.27376545f,  0.95755165f),vec3( 0.28128598f,  0.42443639f, -0.86065785f),vec3(-0.16852403f,  0.14748697f,  0.97460106f)};
	float T = 1.0;
	float alpha = 0.0;
	vec3 ldir = precomputed_sun_dir;
	float ss = length(dir);
	dir = dir/ss;
	vec3 p = pos + hash(pos * 10.0) * ss;
	const float t_dist = cloud_top - cloud_bottom;
	float lss = (t_dist / 36.0);
	vec3 L = vec3(0.0);
	float t = 1.0;
	float costheta = dot(ldir, dir);
	// Stack multiple phase functions to emulate some backscattering
	float phase = max(max(henyey_greenstein(costheta, 0.6), henyey_greenstein(costheta, (0.4 - 1.4 * ldir.y))), henyey_greenstein(costheta, -0.2));
	vec3 atmosphere_sun = precomputed_Atmosphere_sun;
	atmosphere_sun *= ss * cloud_brightness * LIGHT0_ENERGY;
	vec3 atmosphere_ambient = precomputed_Atmosphere_ambient * cloud_ambient_brightness * intensity;
	vec3 atmosphere_ground = precomputed_Atmosphere_ground*ground_color.xyz*ground_brightness * LIGHT0_ENERGY * intensity;

	const float weather_scale = 0.00006;
	const float time = mod(TIME, 100.0) * 0.0003 * _time_scale + 0.005*_time_offset;
	const vec2 weather_pos = vec2(time * 0.9, time);

	for (int i = 0; i < depth; i++) {
		p += dir * ss;
		vec3 weather_sample = texture(weathermap, p.xz * weather_scale + 0.5 + weather_pos).xyz;
		float height_fraction = GetHeightFractionForPoint(length(p));

		t = density(p, weather_sample, 0.0);
		float dt = exp(-_density*t*ss);
		T *= dt;
		vec3 lp = p;
		float lt = 1.0;
		float cd = 0.0;

		if (t > 0.0) { //calculate lighting, but only when we are in the cloud
			for (float j = 0.0; j < 6.0 * sun_visible; j++) {
				lp += (ldir + RANDOM_VECTORS[int(j)]*j)*lss;
				vec3 lweather = texture(weathermap, lp.xz * weather_scale + 0.5 + weather_pos).xyz;
				lt = density(lp, lweather, j);
				cd += lt;
			}

			// Take a single distant sample
			lp = p + ldir * 18.0 * lss;
			float lheight_fraction = GetHeightFractionForPoint(length(lp));
			vec3 lweather = texture(weathermap, lp.xz * weather_scale + 0.5).xyz;
			lt = pow(density(lp, lweather, 5.0), (1.0 - lheight_fraction) * 0.8 + 0.5);
			cd += lt;

			// captures the direct lighting from the sun
			float beers = exp(-_density * cd * lss);
			float beers2 = exp(-_density * cd * lss * 0.25) * 0.7;
			float beers_total = max(beers, beers2);

			vec3 ambient = mix(atmosphere_ground, atmosphere_ambient, smoothstep(0.0, 1.0, height_fraction)) * _density;
//			vec3 ambient = mix(atmosphere_ground, vec3(1.0), smoothstep(0.0, 1.0, height_fraction)) * _density * mix(atmosphere_ambient, vec3(1.0), 0.4); // * (ldir .y);
			alpha += (1.0 - dt) * (1.0 - alpha);
			L += (ambient + beers_total * atmosphere_sun * phase * alpha) * T * t;
		}
	}
	return vec4(L*cloud_brightness, clamp(alpha, 0.0, 1.0));
}

/* End Cloud Parameters */


void sky() {
	vec4 col = vec4(0.0);
	vec3 dir = EYEDIR;
	vec4[2] background = sample_sky(dir, POSITION);
	vec4 col_stars = texture(night_sky, SKY_COORDS) * night_sky_brightness * background[1];
	col = background[0] * intensity * precomputed_sun_enabled;
	col = vec4(col.xyz, 1.0);

	float sun_visible = precomputed_sun_enabled * max(sign(precomputed_sun_dir.y + sin(acos(earthRadius / (earthRadius + cloud_top)) + LIGHT0_SIZE)), 0.0);

	vec3 camPos = vec3(POSITION.x, min(POSITION.y, cloud_bottom) + earthRadius, POSITION.z);
	float cloud_start_distance = solve_quadratic(camPos, dir, cloud_bottom + earthRadius).x;
	float cloud_end_distance = solve_quadratic(camPos, dir, cloud_top + earthRadius).x;
	float avg_dist = (cloud_end_distance+cloud_start_distance)*0.5;


	if (clouds){

		/* Begin Clouds */

		if (AT_HALF_RES_PASS){
			vec4 volume = vec4(0.0);
			vec3 start = camPos + dir * cloud_start_distance;
			vec3 end = camPos + dir * cloud_end_distance;
			float shelldist = (cloud_end_distance-cloud_start_distance);
			
			if (background[0].w<1.0){

				// Take more steps towards horizon, less steps in foggy clouds, and less steps at night
				float steps = ceil(mix(float(cloud_samples_horizon) * (1.0 - 0.5 * (1.0 - sun_visible * (1.0-cloud_coverage))),
											float(cloud_samples_sky) * (1.0 - 0.5 * (1.0 - sun_visible)),
											clamp(sqrt(dir.y), 0.0, 1.0)))*pow(E, -(max(avg_dist, 0.0)*cloud_distance_fade*0.0001));
				vec3 raystep = dir * shelldist / steps;
				volume = march(start, end, raystep, int(steps), sun_visible)*vec4(precomputed_sun_color, 1.0);
				volume.xyz *= precomputed_sun_enabled;

				// Draw cloud shape
				col = vec4(col.xyz*(1.0-volume.a)+volume.xyz, volume.a);
			}

			COLOR = volume.xyz;
			ALPHA = volume.w;
			} else {
				float cloud_fade = pow(E, -(max(avg_dist, 0.0)*cloud_distance_fade*0.001));
				COLOR = col.xyz*(1.0-HALF_RES_COLOR.a*cloud_fade) + HALF_RES_COLOR.xyz*cloud_fade;
				COLOR += col_stars.xyz * (1.0-HALF_RES_COLOR.a)*cloud_fade;
			}

		/* End Clouds */

	} else {
		COLOR = col.xyz+col_stars.xyz;
	}

	// Draw to quarter res buffer for reflections
	// Draw to half res buffer for main sky
//	if (AT_QUARTER_RES_PASS && AT_CUBEMAP_PASS) {
//		COLOR = col.xyz;
//		ALPHA = col.a;
//	} else if (AT_HALF_RES_PASS && !AT_CUBEMAP_PASS) {
//		COLOR = col.xyz;
//		ALPHA = col.a;
//	} else if (AT_CUBEMAP_PASS) {
//		COLOR = QUARTER_RES_COLOR.rgb;
//	} else {
//		COLOR = col.xyz; // Change to col.rgb for full resolution
//	}
}
