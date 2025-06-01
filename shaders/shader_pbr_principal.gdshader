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
uniform mat4 shadow_light_V_matrix_global;
uniform mat4 shadow_light_P_matrix_global;
uniform int shadow_casting_light_idx_global;
uniform float shadow_bias_global;

// --- Uniforms Globais para Light Cookie ---
uniform bool use_spot_cookie;
uniform sampler2D spot_cookie_texture;
uniform mat4 spot_cookie_matrix;
uniform int cookie_light_index;

const float EPSILON = 0.00001;

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

const int DEBUG_VIS_MODE = 0;

void fragment() {
    vec3 frag_world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 view_normal_from_builtin = normalize(NORMAL);
    vec3 frag_world_normal = normalize(mat3(INV_VIEW_MATRIX) * view_normal_from_builtin);
    vec3 world_view_dir = normalize(CAMERA_POSITION_WORLD - frag_world_pos);

    vec3 F0_dielectric = vec3(material_f0_scalar_uniform);
    vec3 F0_metallic = albedo_color_uniform.rgb;
    vec3 effective_F0 = mix(F0_dielectric, F0_metallic, material_metallic_uniform);
    vec3 diffuse_base_color = albedo_color_uniform.rgb * (1.0 - material_metallic_uniform);

    vec3 total_diffuse_lighting = ambient_shader_color_uniform * diffuse_base_color;
    vec3 total_specular_lighting = vec3(0.0);

    vec2 debug_sm_uv = vec2(0.0);
    float debug_depth_from_map = 0.0;
    float debug_current_frag_depth = 0.0;
    float debug_is_in_shadow_factor = 0.5;

    for (int i = 0; i < active_light_count; ++i) {
        if (i >= MAX_LIGHTS) break;

        vec3 current_light_rgb = light_colors[i] * light_intensities[i];
        bool is_current_light_the_shadow_caster = (use_shadow_map_global && i == shadow_casting_light_idx_global);

        if (dot(current_light_rgb, current_light_rgb) < 0.001 && !(DEBUG_VIS_MODE != 0 && is_current_light_the_shadow_caster)) continue;

        vec3 light_dir_to_surface;
        float attenuation = 1.0;
        float spot_effect = 1.0;
        int type = light_types[i];

        if (type == 0) {
            light_dir_to_surface = normalize(light_directions[i]);
        } else {
            vec3 light_vec = light_positions[i] - frag_world_pos;
            float distance_to_light = length(light_vec);
            if (light_ranges[i] > 0.001 && distance_to_light < light_ranges[i]) {
                float norm_dist = distance_to_light / light_ranges[i];
                attenuation = (1.0 - norm_dist * norm_dist);
                attenuation *= attenuation;
                attenuation = max(0.0, attenuation);
            } else {
                attenuation = 0.0;
            }
            light_dir_to_surface = normalize(light_vec);

            if (attenuation > 0.0 && type == 2) {
                vec3 spot_axis = normalize(light_directions[i]);
                vec3 frag_dir_from_light = normalize(-light_dir_to_surface);
                float cos_theta = dot(frag_dir_from_light, spot_axis);
                vec2 cutoffs = light_spot_cos_cutoffs[i];
                spot_effect = smoothstep(cutoffs.y, cutoffs.x, cos_theta);
            }
        }
        attenuation *= spot_effect;

        if (use_spot_cookie && type == 2 && i == cookie_light_index) {
            vec4 cookie_proj_pos = spot_cookie_matrix * vec4(frag_world_pos, 1.0);
            vec2 cookie_uv = (cookie_proj_pos.xy / cookie_proj_pos.w) * 0.5 + 0.5;
            if (cookie_uv.x >= 0.0 && cookie_uv.x <= 1.0 && cookie_uv.y >= 0.0 && cookie_uv.y <= 1.0) {
                attenuation *= texture(spot_cookie_texture, cookie_uv).r;
            } else {
                attenuation = 0.0;
            }
        }

        float shadow_multiplier = 1.0;
        if (is_current_light_the_shadow_caster) {
            mat4 light_VP = shadow_light_P_matrix_global * shadow_light_V_matrix_global;
            vec4 frag_clip_light = light_VP * vec4(frag_world_pos, 1.0);
            vec3 frag_ndc_light = frag_clip_light.xyz / frag_clip_light.w;

            vec2 sm_uv = frag_ndc_light.xy * 0.5 + 0.5;
            float current_depth = frag_ndc_light.z * 0.5 + 0.5;

            debug_sm_uv = sm_uv;
            debug_current_frag_depth = current_depth;

            if (sm_uv.x >= 0.0 && sm_uv.x <= 1.0 && sm_uv.y >= 0.0 && sm_uv.y <= 1.0 && current_depth >= 0.0 && current_depth <= 1.0) {
                float map_depth = texture(shadow_map_sampler_global, sm_uv).r;
                debug_depth_from_map = map_depth;
                if (current_depth > map_depth + shadow_bias_global) {
                    shadow_multiplier = 0.0;
                    debug_is_in_shadow_factor = 1.0;
                } else {
                    debug_is_in_shadow_factor = 0.0;
                }
            } else {
                debug_depth_from_map = -1.0;
                debug_is_in_shadow_factor = 0.25;
            }
        }
        attenuation *= shadow_multiplier;

        if (attenuation <= 0.001 && !(DEBUG_VIS_MODE != 0 && is_current_light_the_shadow_caster)) continue;

        if (DEBUG_VIS_MODE != 0 && is_current_light_the_shadow_caster) {
            // Nenhuma ação para debug
        } else {
            vec3 N = frag_world_normal;
            vec3 V = world_view_dir;
            vec3 L = light_dir_to_surface;
            vec3 H = normalize(L + V);
            float NdotL = max(dot(N, L), 0.0);
            float VdotH = max(dot(V, H), 0.0);

            if (NdotL > 0.0) {
                total_diffuse_lighting += diffuse_base_color * current_light_rgb * NdotL * attenuation;
                float D = NDF_GGX_TR(N, H, material_roughness_uniform);
                float G = Geometry_Smith(N, V, L, material_roughness_uniform);
                vec3 F = Fresnel_Schlick(VdotH, effective_F0);
                float NdotV_clamped = max(dot(N, V), EPSILON);
                vec3 num = D * G * F;
                float den = 4.0 * NdotL * NdotV_clamped;
                total_specular_lighting += current_light_rgb * (num / max(den, EPSILON)) * NdotL * attenuation;
            }
        }
    }

    vec3 final_color_output = total_diffuse_lighting + total_specular_lighting + material_emission_color_uniform;
    float final_alpha_output = albedo_color_uniform.a;

    if (DEBUG_VIS_MODE != 0 && use_shadow_map_global && shadow_casting_light_idx_global != -1 && active_light_count > shadow_casting_light_idx_global) {
        final_alpha_output = 1.0;
        if (DEBUG_VIS_MODE == 1) final_color_output = vec3(debug_sm_uv, 0.0);
        else if (DEBUG_VIS_MODE == 2) final_color_output = vec3(debug_depth_from_map);
        else if (DEBUG_VIS_MODE == 3) final_color_output = vec3(debug_current_frag_depth);
        else if (DEBUG_VIS_MODE == 4) {
            if (debug_is_in_shadow_factor == 1.0) final_color_output = vec3(1.0, 0.0, 0.0);
            else if (debug_is_in_shadow_factor == 0.0) final_color_output = vec3(0.0, 1.0, 0.0);
            else final_color_output = vec3(0.0, 0.0, 1.0);
        }
    }

    ALBEDO = final_color_output;
    ALPHA = final_alpha_output;
}