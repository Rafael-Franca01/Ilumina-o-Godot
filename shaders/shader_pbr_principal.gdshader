shader_type spatial;

uniform vec4 albedo_color_uniform : source_color = vec4(1.0);
uniform vec3 ambient_shader_color_uniform : source_color = vec3(0.1);
uniform float material_roughness_uniform : hint_range(0.0, 1.0) = 0.5;
uniform float material_f0_scalar_uniform : hint_range(0.0, 1.0) = 0.04;
uniform float material_metallic_uniform : hint_range(0.0, 1.0) = 0.0;
uniform vec3 material_emission_color_uniform : source_color = vec3(0.0);

const int MAX_LIGHTS = 8;

uniform vec3 light_positions[MAX_LIGHTS];
uniform vec3 light_colors[MAX_LIGHTS];
uniform float light_intensities[MAX_LIGHTS];
uniform float light_ranges[MAX_LIGHTS];
uniform int light_types[MAX_LIGHTS];
uniform vec3 light_directions[MAX_LIGHTS];
uniform vec2 light_spot_cos_cutoffs[MAX_LIGHTS];
uniform int active_light_count;

const float EPSILON = 0.00001;

float NDF_GGX_TR(vec3 N, vec3 H, float roughness) {
    float alpha = roughness * roughness;
    float alpha_sq = alpha * alpha;
    float NdotH = max(dot(N, H), 0.0);
    float denom = (NdotH * NdotH) * (alpha_sq - 1.0) + 1.0;
    return alpha_sq / (PI * denom * denom + EPSILON);
}

float GeometrySchlickGGX_OneSide(float NdotX, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotX / (NdotX * (1.0 - k) + k + EPSILON);
}

float Geometry_Smith(vec3 N, vec3 V, vec3 L, float roughness) {
    return GeometrySchlickGGX_OneSide(max(dot(N, V), EPSILON), roughness) *
           GeometrySchlickGGX_OneSide(max(dot(N, L), EPSILON), roughness);
}

vec3 Fresnel_Schlick(float cos_theta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}


void fragment() {
    vec3 frag_world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 N = normalize(mat3(INV_VIEW_MATRIX) * NORMAL);
    vec3 V = normalize(CAMERA_POSITION_WORLD - frag_world_pos);

    vec3 albedo = albedo_color_uniform.rgb;
    float metallic = material_metallic_uniform;
    float roughness = material_roughness_uniform;
    
    vec3 F0 = mix(vec3(material_f0_scalar_uniform), albedo, metallic);

    vec3 diffuse_color = albedo * (1.0 - metallic);

    vec3 total_diffuse_lighting = vec3(0.0);
    vec3 total_specular_lighting = vec3(0.0);

    total_diffuse_lighting += ambient_shader_color_uniform * diffuse_color;

    for (int i = 0; i < active_light_count; ++i) {
        if (i >= MAX_LIGHTS) break;

        vec3 light_col = light_colors[i];
        float light_intensity_val = light_intensities[i];
        vec3 light_rgb = light_col * light_intensity_val;

        if (dot(light_rgb, light_rgb) < 0.0001) continue;

        int type = light_types[i];
        vec3 L;
        float attenuation = 1.0;
        float spot_effect = 1.0;

        if (type == 0) {
            vec3 light_vector = light_positions[i] - frag_world_pos;
            float dist_sq = dot(light_vector, light_vector);
            float dist = sqrt(dist_sq);
            L = light_vector / (dist + EPSILON);

            if (light_ranges[i] > 0.001) {
                attenuation = pow(clamp(1.0 - dist / light_ranges[i], 0.0, 1.0), 2.0);
                 if (dist > light_ranges[i]) {
                    attenuation = 0.0;
                 }
            }
             if (attenuation < 0.01) continue;


        } else if (type == 1) { 
            L = normalize(light_directions[i]);
            L = normalize(light_directions[i]);

        } else {
            vec3 light_vector = light_positions[i] - frag_world_pos;
            float dist_sq = dot(light_vector, light_vector);
            float dist = sqrt(dist_sq);
            L = light_vector / (dist + EPSILON);

            if (light_ranges[i] > 0.001) {
                attenuation = pow(clamp(1.0 - dist / light_ranges[i], 0.0, 1.0), 2.0);
                if (dist > light_ranges[i]) {
                    attenuation = 0.0;
                }
            }
            if (attenuation < 0.01) continue;

            float cos_theta = dot(normalize(-L), normalize(light_directions[i]));
            vec2 cutoffs = light_spot_cos_cutoffs[i];
            spot_effect = smoothstep(cutoffs.y, cutoffs.x, cos_theta);
            attenuation *= spot_effect;
            if (attenuation < 0.01) continue;
        }
        
        vec3 H = normalize(V + L);
        float NdotL = clamp(dot(N, L), 0.0, 1.0);

        if (NdotL > 0.0) {
            float D = NDF_GGX_TR(N, H, roughness);
            float G = Geometry_Smith(N, V, L, roughness);
            vec3 F = Fresnel_Schlick(max(dot(H, V), 0.0), F0);

            vec3 kS = F;
            vec3 kD = vec3(1.0) - kS;
            kD *= (1.0 - metallic);

            total_diffuse_lighting += (kD * diffuse_color / PI) * light_rgb * NdotL * attenuation;
            
            vec3 specular_contrib = (D * G * F) / (4.0 * max(dot(N, V), EPSILON) * max(dot(N, L), EPSILON) + EPSILON);
            total_specular_lighting += specular_contrib * light_rgb * NdotL * attenuation;
        }
    }

    vec3 final_color = total_diffuse_lighting + total_specular_lighting + material_emission_color_uniform;

    ALBEDO = final_color;
    ALPHA = albedo_color_uniform.a;
}