#pragma OPENCL EXTENSION cl_khr_fp64 : enable

constant float focal_length    = 500.0;
constant float3 indirect_light = (float3)(0.5f, 0.5f, 0.5f);
constant float3 light_color    = (float3) (14.0f, 14.0f, 14.0f);
#define SCREEN_WIDTH 1024
#define SCREEN_HEIGHT 1024

/////READ ONLY BUFFERS

typedef struct  {
  float3 position;
  float distance;
  int triangle_index;
} Intersection;

inline float det(float3 M[3]) {
	return M[0].x * (M[1].y * M[2].z - M[1].z * M[2].y) -
		   M[0].y * (M[1].x * M[2].z - M[1].z * M[2].x) +
		   M[0].z * (M[1].x * M[2].y - M[1].y * M[2].x);
}

void PutPixelSDL(global uint *screen_buffer, int x, int y, float3 colour) {
  if(x<0 || x>=SCREEN_WIDTH || y<0 || y>=SCREEN_HEIGHT)  {
    printf("apa\n");
    return;
  }
  uint r = (uint) min(max(255*colour.x, 0.f), 255.f);
  uint g = (uint) min(max(255*colour.y, 0.f), 255.f);
  uint b = (uint) min(max(255*colour.z, 0.f), 255.f);
  // if(x<0 && y==0)  {
  screen_buffer[y*SCREEN_WIDTH+x] = (128<<24) + (r<<16) + (g<<8) + b;
}


bool closest_intersection(float3 start, float3 d, global float3 *triangle_vertexes, private Intersection* closest_intersection, int triangle_n) {
  // Set closest intersection to be the max float value
  float current_t = MAXFLOAT;
  // Make 4D ray into 3D ray
  for (uint i = 0; i < triangle_n; i++) {
    // Define two corners of triangle relative to the other corner
    float3 v0 = triangle_vertexes[i*3];
    float3 v1 = triangle_vertexes[i*3+1];
    float3 v2 = triangle_vertexes[i*3+2];

    float3 e1 = (float3) (v1.x-v0.x,    v1.y-v0.y,    v1.z-v0.z);
    float3 e2 = (float3) (v2.x-v0.x,    v2.y-v0.y,    v2.z-v0.z);
    float3 b  = (float3) (start.x-v0.x, start.y-v0.y, start.z-v0.z);

    // Cramers, might be det repeated computation..?
    float3 A[3]  = {-d, e1, e2};
    float3 A0[3] = {b,  e1, e2};
    float3 A1[3] = {-d, b,  e2};
    float3 A2[3] = {-d, e1, b};

    float detA  = det(A);
    float detA0 = det(A0);
    float detA1 = det(A1);
    float detA2 = det(A2); 

    float3 x = (float3) (detA0/detA, detA1/detA, detA2/detA);

    // If ray goes through triangle, and is the closest triangle
    if (x.x >= 0 && x.y >= 0 && x.z >= 0 && (x.y + x.z) <= 1 && x.x < current_t) {
      float3 position = ((float3) (v0.x, v0.y, v0.z)) + (x.y * e1) + (x.z * e2);

      closest_intersection->position = (float3) (position.x, position.y, position.z);
      float3 dist_vec = x.x*d;
      closest_intersection->distance = native_sqrt(dist_vec.x*dist_vec.x + dist_vec.y*dist_vec.y + dist_vec.z*dist_vec.z);
      closest_intersection->triangle_index = i;
      current_t = x.x;
    }
  }
  if (current_t == MAXFLOAT) return false;
  return true;
}


float3 direct_light(const Intersection intersection, global float3 *triangle_vertexes, float3 light_pos, int triangle_n) {

  // Vector from the light to the point of intersection
  float3 r = light_pos - intersection.position;
  // Distance of the checked point to the light source
  float radius = native_sqrt(r.x*r.x + r.y*r.y + r.z*r.z);;

  Intersection obstacle_intersection;
  float threshold = 0.001f;

  if (closest_intersection(intersection.position + (float3) (r.x * threshold, r.y * threshold, r.z * threshold), r, 
  																		triangle_vertexes, &obstacle_intersection, triangle_n)) {
    if (obstacle_intersection.distance < radius) return (float3)(0.0f, 0.0f, 0.0f);
  }

  // Get the normal of the triangle that the light has hit
  float3 n = triangle_vertexes[intersection.triangle_index];
  // Intensity of the colour, based on the distance from the light
  float3 D = (float3) (light_color * max(dot(r, n) , 0.0f)) / (4 * ((float)M_PI) * radius * radius);

  return D;
}


kernel void draw(global uint  *screen_buffer,    global float3 *triangle_vertexes,   global float3 *triangle_normals,
				 global float3 *triangle_colors, global float3 *rot_matrix,           float3 camera_pos, float3 light_pos, int triangle_n)
{         /* accumulated magnitudes of velocity for each cell */
  const short x = get_global_id(0);
  const short y = get_global_id(1);



  if(x==0 && y==0)   {
  	// printf("r 0 %f 1 %f 2 %f\n", rot_matrix[0].x, rot_matrix[0].y, rot_matrix[0].z);
  	// printf("r 3 %f 4 %f 5 %f\n", rot_matrix[1].x, rot_matrix[1].y, rot_matrix[1].z);
  	// printf("r 6 %f 7 %f 8 %f\n", rot_matrix[2].x, rot_matrix[2].y, rot_matrix[2].z);
  	printf("light.pos 0 %f 1 %f 2 %f\n", light_pos.x, light_pos.y, light_pos.z);
  }


  // Declare ray for given position on the screen. Rotate ray by current view angle
  float3 d = (float3) (x - SCREEN_WIDTH/2.0, y - SCREEN_HEIGHT/2.0, focal_length);
  d        = (float3) (dot(rot_matrix[0], d), dot(rot_matrix[1], d), dot(rot_matrix[2], d));

  // Find intersection point with closest geometry. If no intersection, paint the abyss
  Intersection intersection;
  if (closest_intersection(camera_pos, d, triangle_vertexes, &intersection, triangle_n)) {
    float3 p = triangle_colors[intersection.triangle_index];
    float3 final_color = p*(direct_light(intersection, triangle_vertexes, light_pos, triangle_n) + indirect_light);
  	PutPixelSDL(screen_buffer, x, y, final_color);

  } else {
    // Otherwise draw black
  	PutPixelSDL(screen_buffer, x, y, (float3) (0.0f, 0.0f, 0.0f));
  }
}





