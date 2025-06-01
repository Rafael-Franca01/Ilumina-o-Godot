shader_type spatial;

// --- Uniforms do Material ---
uniform vec4 albedo_color_uniform : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec3 ambient_shader_color_uniform : source_color = vec3(0.1, 0.1, 0.1);
uniform float material_roughness_uniform : hint_range(0.0, 1.0) = 0.5;
uniform float material_f0_scalar_uniform : hint_range(0.0, 1.0) = 0.04; // F0 para dielétricos
uniform float material_metallic_uniform : hint_range(0.0, 1.0) = 0.0;
uniform vec3 material_emission_color_uniform : source_color = vec3(0.0, 0.0, 0.0);

// --- Uniforms das Luzes (Arrays) ---
const int MAX_LIGHTS = 8;
uniform vec3 light_positions[MAX_LIGHTS];
uniform vec3 light_colors[MAX_LIGHTS];
uniform float light_intensities[MAX_LIGHTS];
uniform float light_ranges[MAX_LIGHTS];
uniform int light_types[MAX_LIGHTS]; // 0:DIRECTIONAL, 1:POINT, 2:SPOT
uniform vec3 light_directions[MAX_LIGHTS];
uniform vec2 light_spot_cos_cutoffs[MAX_LIGHTS]; // .x = cos_inner, .y = cos_outer
uniform int active_light_count;

// --- Uniforms Globais para Sombra ---
uniform bool use_shadow_map_global;
uniform sampler2D shadow_map_sampler_global : hint_depth_texture;
uniform mat4 shadow_light_V_matrix_global; // Matriz View da Luz de Sombra
uniform mat4 shadow_light_P_matrix_global; // Matriz Projection da Luz de Sombra
uniform int shadow_casting_light_idx_global;
uniform float shadow_bias_global;

// --- Uniforms Globais para Light Cookie ---
uniform bool use_spot_cookie;
uniform sampler2D spot_cookie_texture;
uniform mat4 spot_cookie_matrix; // World -> UV do Cookie
uniform int cookie_light_index;

// Constantes
// PI é embutido.
const float EPSILON = 0.00001;

// --- Funções Auxiliares PBR ---
float NDF_GGX_TR(vec3 N, vec3 H, float roughness) {
	float alpha = roughness * roughness;
	float alpha_sq = alpha * alpha;
	float NdotH = max(dot(N, H), 0.0);
	float NdotH_sq = NdotH * NdotH;
	float denom_part = NdotH_sq * (alpha_sq - 1.0) + 1.0;
	return alpha_sq / (PI * denom_part * denom_part + EPSILON);
}

float GeometrySchlickGGX_OneSide(float NdotX, float roughness) {
	float r_plus_1 = roughness + 1.0;
	float k = (r_plus_1 * r_plus_1) / 8.0;
	return NdotX / (NdotX * (1.0 - k) + k + EPSILON);
}

float Geometry_Smith(vec3 N, vec3 V, vec3 L, float roughness) {
	float NdotV = max(dot(N, V), EPSILON);
	float NdotL = max(dot(N, L), EPSILON);
	float ggx_v = GeometrySchlickGGX_OneSide(NdotV, roughness);
	float ggx_l = GeometrySchlickGGX_OneSide(NdotL, roughness);
	return ggx_v * ggx_l;
}

vec3 Fresnel_Schlick(float cos_theta_incident, vec3 F0_effective_color) {
	return F0_effective_color + (vec3(1.0) - F0_effective_color) * pow(clamp(1.0 - cos_theta_incident, 0.0, 1.0), 5.0);
}

void fragment() {
	// Transformações para World Space (Modo de Compatibilidade)
	vec3 frag_world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 view_normal_from_builtin = normalize(NORMAL);
	vec3 frag_world_normal = normalize(mat3(INV_VIEW_MATRIX) * view_normal_from_builtin);
	vec3 world_view_dir = normalize(CAMERA_POSITION_WORLD - frag_world_pos); // V

	// Determinar Propriedades PBR Baseadas em Metálico
	vec3 F0_dielectric = vec3(material_f0_scalar_uniform);
	vec3 F0_metallic = albedo_color_uniform.rgb;
	vec3 effective_F0 = mix(F0_dielectric, F0_metallic, material_metallic_uniform);
	vec3 diffuse_base_color = albedo_color_uniform.rgb * (1.0 - material_metallic_uniform);

	// Inicialização da Iluminação
	vec3 total_diffuse_lighting = ambient_shader_color_uniform * diffuse_base_color;
	vec3 total_specular_lighting = vec3(0.0, 0.0, 0.0);

	// Loop Pelas Luzes
	for (int i = 0; i < active_light_count; ++i) {
		if (i >= MAX_LIGHTS) break;

		vec3 current_light_rgb = light_colors[i] * light_intensities[i];
		if (dot(current_light_rgb, current_light_rgb) < 0.001) continue;

		vec3 light_dir_to_surface; // Vetor da superfície PARA a fonte de luz
		float attenuation = 1.0;
		float spot_effect = 1.0;
		int type = light_types[i];

		if (type == 0) { // Directional
			light_dir_to_surface = normalize(light_directions[i]);
			attenuation = 1.0;
		} else { // Point ou Spot
			vec3 light_vec = light_positions[i] - frag_world_pos;
			float distance_to_light = length(light_vec);

			if (light_ranges[i] > 0.001 && distance_to_light < light_ranges[i]) {
				float norm_dist = distance_to_light / light_ranges[i];
				attenuation = (1.0 - norm_dist * norm_dist);
				attenuation *= attenuation; // ao quadrado
				attenuation = max(0.0, attenuation);
			} else {
				attenuation = 0.0;
			}
			light_dir_to_surface = normalize(light_vec);

			if (attenuation > 0.0 && type == 2) { // Spot Light
				vec3 spot_axis = normalize(light_directions[i]);
				vec3 frag_dir_from_light = normalize(-light_dir_to_surface);
				float cos_theta = dot(frag_dir_from_light, spot_axis);
				vec2 cutoffs = light_spot_cos_cutoffs[i]; // .x = cos_inner, .y = cos_outer
				spot_effect = smoothstep(cutoffs.y, cutoffs.x, cos_theta);
			}
		}
		attenuation *= spot_effect;

		// Aplicação do Light Cookie
		if (use_spot_cookie && type == 2 && i == cookie_light_index) {
			vec4 cookie_proj_pos = spot_cookie_matrix * vec4(frag_world_pos, 1.0);
			vec2 cookie_uv = (cookie_proj_pos.xy / cookie_proj_pos.w) * 0.5 + 0.5;
			if (cookie_uv.x >= 0.0 && cookie_uv.x <= 1.0 &&
				cookie_uv.y >= 0.0 && cookie_uv.y <= 1.0) {
				float cookie_val = texture(spot_cookie_texture, cookie_uv).r;
				attenuation *= cookie_val;
			} else {
				attenuation = 0.0; // Fora da projeção do cookie
			}
		}
		
		// Aplicação da Sombra
		float shadow_multiplier = 1.0;
		if (use_shadow_map_global && i == shadow_casting_light_idx_global) {
			mat4 light_VP_matrix = shadow_light_P_matrix_global * shadow_light_V_matrix_global;
			vec4 frag_pos_light_clip = light_VP_matrix * vec4(frag_world_pos, 1.0);
			vec3 frag_pos_light_ndc = frag_pos_light_clip.xyz / frag_pos_light_clip.w;
			
			// CORREÇÃO: Mapeia NDC.z de [-1, 1] para [0, 1]
			float current_depth_from_light = frag_pos_light_ndc.z * 0.5 + 0.5; 

			vec2 shadow_map_uv = frag_pos_light_ndc.xy * 0.5 + 0.5;

			if (shadow_map_uv.x >= 0.0 && shadow_map_uv.x <= 1.0 &&
				shadow_map_uv.y >= 0.0 && shadow_map_uv.y <= 1.0 &&
				current_depth_from_light >= 0.0 && current_depth_from_light <= 1.0) {

				float depth_from_shadow_map = texture(shadow_map_sampler_global, shadow_map_uv).r;

				if (current_depth_from_light > depth_from_shadow_map + shadow_bias_global) {
					shadow_multiplier = 0.0; // Em sombra
				}
			}
			// Se estiver fora do frustum da sombra (UVs ou profundidade), shadow_multiplier permanece 1.0 (não sombreado por este mapa)
		}
		attenuation *= shadow_multiplier;
		
		if (attenuation <= 0.001) continue;

		// Vetores PBR
		vec3 N = frag_world_normal;
		vec3 V = world_view_dir;
		vec3 L = light_dir_to_surface;
		vec3 H = normalize(L + V);

		float NdotL = max(dot(N, L), 0.0);
		float NdotV = max(dot(N, V), EPSILON); 
		float VdotH = max(dot(V, H), 0.0);

		if (NdotL > 0.0) { // Só calcula iluminação se a luz atinge a frente
			// Difusa
			total_diffuse_lighting += diffuse_base_color * current_light_rgb * NdotL * attenuation;
			
			// Especular PBR
			float D_ggx = NDF_GGX_TR(N, H, material_roughness_uniform);
			float G_smith = Geometry_Smith(N, V, L, material_roughness_uniform);
			vec3 F_schlick = Fresnel_Schlick(VdotH, effective_F0);
			
			vec3 numerator = D_ggx * G_smith * F_schlick;
			float denominator = 4.0 * NdotL * NdotV;
			
			vec3 specular_pbr_term = numerator / max(denominator, EPSILON);
			total_specular_lighting += current_light_rgb * specular_pbr_term * NdotL * attenuation;
		}
	}

	vec3 final_color = total_diffuse_lighting + total_specular_lighting + material_emission_color_uniform;
	
	ALBEDO = final_color;
	ALPHA = albedo_color_uniform.a;
}