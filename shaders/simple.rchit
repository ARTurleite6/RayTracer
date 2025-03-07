/* Copyright (c) 2019-2024, Sascha Willems
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 the "License";
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_scalar_block_layout : require

struct Material {
    vec3 albedo;
};

struct ObjectData {
    uint material_index;
};

layout(location = 0) rayPayloadInEXT vec3 payload;

layout(set = 2, binding = 0, scalar) buffer MaterialsBuffer {
    Material materials[];
};

layout(set = 2, binding = 1, scalar) buffer ObjectsData {
    ObjectData objects[];
};

void main()
{
    ObjectData object = objects[gl_InstanceCustomIndexEXT];
    Material mat = materials[object.material_index];
    payload = mat.albedo;
}
