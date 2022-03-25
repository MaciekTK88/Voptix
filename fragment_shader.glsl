#version 300 es

precision mediump float;
precision mediump sampler3D;

// size of single octree leaf
#define VOXEL_SIZE 2

// channel offsets
#define RED 0
#define GREEN 1
#define BLUE 2
#define ALPHA 3
//#define CLARITY 0

const int chunk_size = 128;

const int chunk_count = 9;

out vec4[3] outColor;
uniform sampler3D u_textures[chunk_count];
uniform sampler2D noise;
uniform vec3[6] scene_data;
uniform ivec3[3] chunk_map;

vec4 getVoxel(ivec3 pos, int i, int level) {
	ivec3 chu = pos / chunk_size;
	int chunk = chunk_map[chu.z][chu.x];
	pos = pos % chunk_size;
	pos.x = pos.x * 2 + i;

	vec4 fvoxel;
	if (chunk == 0)
		fvoxel = texelFetch(u_textures[0], pos, level);
	else if (chunk == 1)
		fvoxel = texelFetch(u_textures[1], pos, level);
	else if (chunk == 2)
		fvoxel = texelFetch(u_textures[2], pos, level);
	else if (chunk == 3)
		fvoxel = texelFetch(u_textures[3], pos, level);
	else if (chunk == 4)
		fvoxel = texelFetch(u_textures[4], pos, level);
	else if (chunk == 5)
		fvoxel = texelFetch(u_textures[5], pos, level);
	else if (chunk == 6)
		fvoxel = texelFetch(u_textures[6], pos, level);
	else if (chunk == 7)
		fvoxel = texelFetch(u_textures[7], pos, level);
	else if (chunk == 8)
		fvoxel = texelFetch(u_textures[8], pos, level);

	return fvoxel;
}

struct Ray {
	vec3 orig;
	vec3 dir;
};

struct Scene {
	vec3 camera_origin;
	vec3 camera_direction;
	vec3 chunk_offset;
	vec3 screen;
	vec3 background;
	vec3 projection;
};

struct OctreeData {
	vec3 xyzo;
	float csize;
	float layerindex;
	int oc;
	int mask;
};

void load_direction(inout vec3 vec, vec3 rotation) {
	float rotated;

	float cosx = cos(rotation.x);
	float cosy = cos(rotation.y);

	float sinx = sin(rotation.x);
	float siny = sin(rotation.y);

	rotated = vec.z * cosx + vec.y * sinx;
	vec.y = vec.y * cosx - vec.z * sinx;
	vec.z = rotated;

	rotated = vec.x * cosy - vec.z * siny;
	vec.z = vec.z * cosy + vec.x * siny;
	vec.x = rotated;
}

void load_ray(inout Ray ray, vec3 direction, vec3 origin) {

	ray.orig = origin;
	ray.dir = normalize(direction);
}

// initialize ray object
void load_primary_ray(inout Ray ray, Scene scene, vec2 pos, const float width, const float height, float fov) {
	float aspect_ratio = width / height;

	vec3 dir;
	dir.x = (2.0f * pos.x / width - 1.0f) * aspect_ratio * fov;
	dir.y = (2.0f * pos.y / height - 1.0f) * fov;
	dir.z = 1.0f;

	vec3 rotation = vec3(
		scene.camera_direction.y,
		scene.camera_direction.x,
		0.0f
	);

	load_direction(dir, rotation);

	load_ray(ray, dir, scene.camera_origin);
}

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void Bounce(inout Ray ray, vec3 hit, vec3 box_pos, float size) {

	ray.orig = hit;
	ray.dir.x *= ((hit.x >= box_pos.x + size || hit.x <= box_pos.x - size) ? -1.0f : 1.0f);
	ray.dir.y *= ((hit.y >= box_pos.y + size || hit.y <= box_pos.y - size) ? -1.0f : 1.0f);
	ray.dir.z *= ((hit.z >= box_pos.z + size || hit.z <= box_pos.z - size) ? -1.0f : 1.0f);
}

// draw single pixel queried from octree with a 3D ray
void octree_get_pixel(Ray ray, inout float max_dist, inout vec4 voutput, inout vec4 matoutput, int octree_depth, inout vec3 box_pos) {

	vec3 ndir = ray.dir;

	//length of vector to add for single step (hypotenuse)
	vec3 unitStepSize = vec3(abs(1.0f / ndir.x), abs(1.0f / ndir.y), abs(1.0f / ndir.z));
	/*vec3 unitStepSize = vec3(sqrt(1.0f + pow(ndir.z / ndir.x, 2.0f) + pow(ndir.y / ndir.x, 2.0f)),
		sqrt(1.0f + pow(ndir.x / ndir.y, 2.0f) + pow(ndir.z / ndir.y, 2.0f)),
		sqrt(1.0f + pow(ndir.x / ndir.z, 2.0f) + pow(ndir.y / ndir.z, 2.0f))
	);*/


	vec3 rayLength1D = vec3(0.0f);

	ivec3 vStep = ivec3(1);

	ivec3 testPos = ivec3(ray.orig);

	if (ray.dir.x < 0.0f) {
		vStep.x = -1;
		rayLength1D.x = (ray.orig.x - float(testPos.x)) * unitStepSize.x;
	}
	else {
		vStep.x = 1;
		rayLength1D.x = (float(testPos.x + 1) - ray.orig.x) * unitStepSize.x;
	}

	if (ray.dir.y < 0.0f) {
		vStep.y = -1;
		rayLength1D.y = (ray.orig.y - float(testPos.y)) * unitStepSize.y;
	}
	else {
		vStep.y = 1;
		rayLength1D.y = (float(testPos.y + 1) - ray.orig.y) * unitStepSize.y;
	}

	if (ray.dir.z < 0.0f) {
		vStep.z = -1;
		rayLength1D.z = (ray.orig.z - float(testPos.z)) * unitStepSize.z;
	}
	else {
		vStep.z = 1;
		rayLength1D.z = (float(testPos.z + 1) - ray.orig.z) * unitStepSize.z;
	}

	float dist = 0.0f;
	bool vHit = false;
	while (!vHit && dist < max_dist) {
		if (rayLength1D.x < rayLength1D.y && rayLength1D.x < rayLength1D.z) {
			testPos.x += vStep.x;
			dist = rayLength1D.x;
			rayLength1D.x += unitStepSize.x;
		}
		else {
			if (rayLength1D.y < rayLength1D.z) {
				testPos.y += vStep.y;
				dist = rayLength1D.y;
				rayLength1D.y += unitStepSize.y;
			}
			else {
				testPos.z += vStep.z;
				dist = rayLength1D.z;
				rayLength1D.z += unitStepSize.z;
			}
		}

		if (testPos.x >= 0 && testPos.y >= 0 && testPos.z >= 0 && testPos.x < chunk_size * 3 && testPos.y < chunk_size && testPos.z < chunk_size * 3) {
			if (getVoxel(testPos, 0, 0).w > 0.0f) {
				vHit = true;
			}
		}
	}


	if (dist < max_dist && vHit) {
		max_dist = dist;

		vec4 vox = getVoxel(testPos, 0, 0);
		vec4 vox_mat = getVoxel(testPos, 1, 0);
		voutput.x = vox.x;
		voutput.y = vox.y;
		voutput.z = vox.z;
		voutput.w = dist;

		//clarity
		matoutput = vox_mat;

		box_pos = vec3(testPos);
		box_pos.x += 0.5f;
		box_pos.y += 0.5f;
		box_pos.z += 0.5f;
	}
}

//AO test
bool occlusion(ivec3 delta_pos, ivec3 box_pos, int scx, int scz) {
	ivec3 test = box_pos + delta_pos;
	if (test.y < 0 || test.y >= chunk_size) return false;
	return (getVoxel(test, 0, 0).w > 0.0f);
}

void main() {

	Scene scene = Scene(
		scene_data[0],
		scene_data[1],
		scene_data[2],
		scene_data[3],
		scene_data[4],
		scene_data[5]
	);

	vec2 pos = vec2(gl_FragCoord.x, gl_FragCoord.y);

	float fov = scene.projection.x;
	float near = scene.projection.y;
	float far = 255.0f;//scene.projection.z;

	// set background color
	vec4 pixel_color = vec4(scene.background.x, scene.background.y, scene.background.z, far);

	const float ray_retreat = 0.01f;

	Ray ray;
	load_primary_ray(ray, scene, pos, scene.screen.x, scene.screen.y, tan(fov / 2.0f));
	Ray primary_ray = ray;

	int octree_depth = 6;

	vec4 prevmat = vec4(0, 0, 0, 0);
	vec4 tmpmat = vec4(0, 0, 0, 0);
	vec4 illumination = vec4(0);
	vec3 prim_box_pos = vec3(0, 0, 0);

	for (int bounces = 0; bounces < 3; bounces++) {
		vec4 ray_pixel_color = vec4(scene.background.x, scene.background.y, scene.background.z, far);
		vec3 hit = vec3(0, 0, 0);
		vec3 box_pos = vec3(0, 0, 0);
		vec4 vmat = vec4(0, 0, 0, 0);

		int samples = 2;//(bounces == 0) ? 3 : 2;
		for (int spp = 0; spp < samples; spp++) {

			vec4 color = vec4(scene.background.x, scene.background.y, scene.background.z, far);
			float max_dist = far;
			//float size = chunk_size;

			/*vec3 bounds[2] = vec3[2](
				chunk_pos,
				chunk_pos + size
				);*/

			float tmp_dist = 0.0f;
			//if (intersects(ray, bounds, tmp_dist)) {

				// 222 = csize * sqrt(3)
				//if (tmp_dist > -222.0f && tmp_dist < max_dist) {

					// render the chunk
			vec3 box_pos_t = vec3(-1, -1, -1);
			octree_get_pixel(ray, max_dist, color, tmpmat, octree_depth, box_pos_t);
			if (spp == 0 && box_pos_t.x != -1.0f) {
				box_pos = box_pos_t;
				vmat = tmpmat;
			}
			//}
		//}

			if (spp == 0) {
				ray_pixel_color = color;
				if (bounces == 0) prim_box_pos = box_pos;
				float w = ray_pixel_color.w;
				if ((int(vmat.x * 255.0f) & 15) > 0) ray_pixel_color += vec4(float((int(vmat.x * 255.0f) & 15) << 4) / 255.0f) * color;
				ray_pixel_color.w = w;
			}
			else if (spp == 1) {
				ray_pixel_color.x = ((color.w >= far) ? ray_pixel_color.x : ray_pixel_color.x * 0.5f);
				ray_pixel_color.y = ((color.w >= far) ? ray_pixel_color.y : ray_pixel_color.y * 0.5f);
				ray_pixel_color.z = ((color.w >= far) ? ray_pixel_color.z : ray_pixel_color.z * 0.5f);
				//if (color.w >= far) illumination = vec4(1,1,1,1);
			}
			else {
				if ((int(tmpmat.x * 255.0f) & 15) > 0 && color.w < far)
					illumination = vec4(float((int(tmpmat.x * 255.0f) & 15) << 4) / 255.0f) * color;
			}
			if (color.w >= far && spp == 0) {
				break;
			}
			else {
				ray = primary_ray;
				color = ray_pixel_color;

				vec3 origin = vec3(
					ray.orig.x + ray.dir.x * (color.w - ray_retreat),
					ray.orig.y + ray.dir.y * (color.w - ray_retreat),
					ray.orig.z + ray.dir.z * (color.w - ray_retreat)
				);

				if (spp == 0) hit = origin;

				vec3 dir;
				if (spp < 1) {
					//shadow ray
					dir = vec3(
						2.0f,
						1.0f,
						-1.0f
					);
				}
				else {
					//float rn = rand(pos + vec2(scene.screen.z)) * 2.0f - 1.0f;
					//float rn1 = rand(vec2(rn * 200.0f, rn * 123.0f)) * 2.0f - 1.0f;
					//float rn2 = rand(vec2(rn1 * 200.0f, rn1 * 123.0f));
					vec4 rnd = texelFetch(noise, ivec2(pos), 0);
					rnd.x = rnd.x * 2.0f - 1.0f;
					rnd.y = rnd.y * 2.0f - 1.0f;
					/*dir = vec3(
						rn,
						rn1,
						rn2
					);*/

					dir = ray.dir;

					if ((hit.x >= box_pos.x + 0.5f || hit.x <= box_pos.x - 0.5f)) {
						dir.x = sign(-dir.x) * rnd.z;
						dir.y = rnd.x;
						dir.z = rnd.y;
					}
					if ((hit.y >= box_pos.y + 0.5f || hit.y <= box_pos.y - 0.5f)) {
						dir.y = sign(-dir.y) * rnd.z;
						dir.x = rnd.x;
						dir.z = rnd.y;
					}
					if ((hit.z >= box_pos.z + 0.5f || hit.z <= box_pos.z - 0.5f)) {
						dir.z = sign(-dir.z) * rnd.z;
						dir.y = rnd.x;
						dir.x = rnd.y;
					}

				}

				load_ray(ray, dir, origin);
			}
		}

		if (ray_pixel_color.w >= far) {
			ray_pixel_color.x = scene.background.x;
			ray_pixel_color.y = scene.background.y;
			ray_pixel_color.z = scene.background.z;
		}

		if (bounces == 0) {
			pixel_color = ray_pixel_color;

			//AO
			const float size = 0.5f;
			if (ray_pixel_color.w < far) {
				bool a = hit.x >= box_pos.x + size;
				bool b = hit.x <= box_pos.x - size;
				float shade = 0.0f;
				if (a || b) {
					int x = (a) ? 1 : -1;

					for (int y = -1; y < 2; y++) {
						for (int z = -1; z < 2; z++) {
							if (!(y == 0 && z == 0) && occlusion(ivec3(x, y, z), ivec3(box_pos), int(scene.chunk_offset.x), int(scene.chunk_offset.z))) {
								float bl = 0.0f;
								if (abs(z * y) > 0) {
									bl = (1.0f - sqrt(pow(box_pos.z + float(z) * 0.5f - hit.z, 2.0f) + pow(box_pos.y + float(y) * 0.5f - hit.y, 2.0f)));
								}
								else {
									bl = (((y == 0) ? 0.0f : abs(box_pos.y - float(y) * 0.5f - hit.y))
										+ ((z == 0) ? 0.0f : abs(box_pos.z - float(z) * 0.5f - hit.z)));
								}
								shade = max(bl, shade);
							}
						}
					}
				}
				else {
					a = hit.y >= box_pos.y + size;
					b = hit.y <= box_pos.y - size;
					if (a || b) {
						int y = (a) ? 1 : -1;
						for (int x = -1; x < 2; x++) {
							for (int z = -1; z < 2; z++) {
								if (!(x == 0 && z == 0) && occlusion(ivec3(x, y, z), ivec3(box_pos), int(scene.chunk_offset.x), int(scene.chunk_offset.z))) {
									float bl = 0.0f;
									if (abs(z * x) > 0) {
										bl = (1.0f - sqrt(pow(box_pos.z + float(z) * 0.5f - hit.z, 2.0f) + pow(box_pos.x + float(x) * 0.5f - hit.x, 2.0f)));
									}
									else {
										bl = (((x == 0) ? 0.0f : abs(box_pos.x - float(x) * 0.5f - hit.x))
											+ ((z == 0) ? 0.0f : abs(box_pos.z - float(z) * 0.5f - hit.z)));
									}
									shade = max(bl, shade);
								}
							}
						}
					}
					else {
						a = hit.z >= box_pos.z + size;
						b = hit.z <= box_pos.z - size;
						if (a || b) {
							int z = (a) ? 1 : -1;
							for (int x = -1; x < 2; x++) {
								for (int y = -1; y < 2; y++) {
									if (!(y == 0 && x == 0) && occlusion(ivec3(x, y, z), ivec3(box_pos), int(scene.chunk_offset.x), int(scene.chunk_offset.z))) {
										float bl = 0.0f;
										if (abs(y * x) > 0) {
											bl = (1.0f - sqrt(pow(box_pos.y + float(y) * 0.5f - hit.y, 2.0f) + pow(box_pos.x + float(x) * 0.5f - hit.x, 2.0f)));
										}
										else {
											bl = (((y == 0) ? 0.0f : abs(box_pos.y - float(y) * 0.5f - hit.y))
												+ ((x == 0) ? 0.0f : abs(box_pos.x - float(x) * 0.5f - hit.x)));
										}
										shade = max(bl, shade);
									}
								}
							}
						}
					}
				}
				pixel_color = mix(pixel_color, vec4(0.0f, 0.0f, 0.0f, ray_pixel_color.w), pow(shade, 2.0f) * 0.1f);
			}

			//pixel_color.x = clamp(vmat.y + pixel_color.x, 0.0f, 1.0f);
			//pixel_color.y = clamp(vmat.z + pixel_color.y, 0.0f, 1.0f);
			//pixel_color.z = clamp(vmat.w + pixel_color.z, 0.0f, 1.0f);

			//pixel_color.x = vmat.y;
			//pixel_color.y = vmat.z;
			//pixel_color.z = vmat.w;
		}
		else {
			float intensity = float(int(prevmat.x * 255.0f) & 240) / 100.0f;
			pixel_color.x = clamp((pixel_color.x + ray_pixel_color.x * intensity) / (1.0f + intensity), 0.0f, 1.0f);
			pixel_color.y = clamp((pixel_color.y + ray_pixel_color.y * intensity) / (1.0f + intensity), 0.0f, 1.0f);
			pixel_color.z = clamp((pixel_color.z + ray_pixel_color.z * intensity) / (1.0f + intensity), 0.0f, 1.0f);
		}

		if ((int(vmat.x * 255.0f) & 240) < 1) break;
		else prevmat = vmat;

		if (ray_pixel_color.w >= far) break;
		Bounce(primary_ray, hit, box_pos, 0.5f);
		ray = primary_ray;
	}
	//if (illumination.w > 0.0f) {
	//	pixel_color.x = illumination.x;//mix(pixel_color.x, illumination.x, 0.5f);
	//	pixel_color.y = illumination.y;// mix(pixel_color.y, illumination.y, 0.5f);
	//	pixel_color.z = illumination.z;//mix(pixel_color.z, illumination.z, 0.5f);
	//}
	float w = pixel_color.w;
	pixel_color = clamp(pixel_color, 0.0f, 1.0f);
	pixel_color.w = w;
	outColor[0] = vec4(pixel_color.x, pixel_color.y, pixel_color.z, clamp(pixel_color.w / 255.0f * 2.0f, 0.0f, 1.0f));
	outColor[1] = vec4(1.0f);
	outColor[2] = vec4(1.0f);
	//0b11100000 0b00011100
	//vec4 outColorValue = vec4(floor(prim_box_pos.x), floor(prim_box_pos.y), floor(prim_box_pos.z), (int(illumination.x * 255.0f) & 224) + ((int(illumination.y * 255.0f) >> 3) & 28) + (int(illumination.z * 255.0f) >> 6));
	//outColor[1] = outColorValue / 255.0f;//vec4(prim_box_pos.x, illumination.y, illumination.z, illumination.z);//
	//outColor[1] = vec4(floor(prim_box_pos.x), floor(prim_box_pos.y), floor(prim_box_pos.z), 0.0f) / 255.0f;
	//outColor[2] = vec4(illumination.x, illumination.y, illumination.z, 0.0f);
}
