#ifndef FF_WATER_SPECULAR_INCLUDED
#define FF_WATER_SPECULAR_INCLUDED

#include "ff_WaterCommon.hlsl"

float FFCalculateSpecular(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float shininess,
    float specularPower)
{
    float FFCalculateSpecularGGX(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float roughness,
    float specularPower)
{
    float3 FFCalculateSpecularBlinPhong(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float roughness)
    float specularPower)
{
    float3 FFCalculateEnvReflection(
    float3 normalWS,
    float3 viewDirWS,
    float roughness,
    float envReflectionStrength)
{
    float3 FFGetSpecularDominantDirection(
    float3 normalWS,
    float3 viewDirWS)
{
    float3 FFGetReflectionColor(
    float3 normalWS,
    float3 viewDirWS,
    float fresnel)
{
    float3 FFGetReflectionColorWithEnvMap(
    float3 normalWS,
    float3 viewDirWS,
    float fresnel,
    float envStrength)
{
    float3 FFBlendSpecularEnv(
    float3 specular,
    float3 envReflection,
    float fresnel
    float envStrength
)
{
    float FFSampleEnvReflection(
    float3 reflectDir,
    float roughness,
    float envStrength)
}
    float3 FFSampleEnvReflectionWithFresnel(
    float3 reflectDir,
    float roughness,
    float envStrength,
    float fresnel
)
#endif
