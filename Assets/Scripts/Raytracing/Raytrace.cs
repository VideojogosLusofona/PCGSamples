using NaughtyAttributes;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using UnityEngine;
using Unity.VisualScripting;
using System;

[ExecuteAlways]
public class Raytrace : MonoBehaviour
{
    [SerializeField] private ComputeShader  compute;
    [SerializeField] private RenderTexture  renderTarget;
    [SerializeField] private Camera         renderCamera;
    [SerializeField] private Color          ambientColor = Color.cornflowerBlue;
    [SerializeField] private int            maxBounces = 8;
    [SerializeField] private int            reflectionRayCount = 8;
    [SerializeField] private bool           renderEnable = false;
    [SerializeField] private bool           alwaysUpdateScene = true;

    ComputeBuffer primitiveBuffer;
    ComputeBuffer materialBuffer;
    ComputeBuffer lightBuffer;

    void Start()
    {
        SetupScene();        
    }

    void Update()
    {
        if (renderEnable)
        {
            if (alwaysUpdateScene) SetupScene();
            Execute();
        }
    }

    [Button("SetupScene")]
    void SetupScene()
    {
        primitiveBuffer?.Release();
        materialBuffer?.Release();

        var materials = new List<RTMaterial>();
        var primitives = new List<GPUPrimitive>();
        var lights = new List<GPULight>();

        var primitivesObj = FindObjectsByType<RTPrimitive>(FindObjectsSortMode.None);
        foreach (var primitive in primitivesObj)
        {
            var p = primitive.GetGPUPrimitive();
            p.material = materials.Count;
            primitives.Add(p);
            materials.Add(primitive.GetMaterial());
        }

        var lightsObj = FindObjectsByType<RTLight>(FindObjectsSortMode.None);
        foreach (var light in lightsObj)
        {
            lights.Add(light.GetGPULight());
        }

        primitiveBuffer = new ComputeBuffer(Mathf.Max(1, primitives.Count), Marshal.SizeOf<GPUPrimitive>(), ComputeBufferType.Structured);
        materialBuffer = new ComputeBuffer(Mathf.Max(1, materials.Count), Marshal.SizeOf<RTMaterial>(), ComputeBufferType.Structured);
        lightBuffer = new ComputeBuffer(Mathf.Max(1, lights.Count), Marshal.SizeOf<GPULight>(), ComputeBufferType.Structured);

        primitiveBuffer.SetData(primitives);
        materialBuffer.SetData(materials);
        lightBuffer.SetData(lights);
    }

    static bool errorLogged = false;

    [Button("Raytrace")]
    protected void Execute()
    {
        int kernel = compute.FindKernel("CSMain");

        // Setup primitives
        if ((primitiveBuffer == null) || (materialBuffer == null))
        {
            SetupScene();
        }

        compute.SetBuffer(kernel, "_Primitives", primitiveBuffer);
        compute.SetBuffer(kernel, "_Materials", materialBuffer);
        compute.SetBuffer(kernel, "_Lights", lightBuffer);
        compute.SetInt("_PrimitiveCount", primitiveBuffer.count);
        compute.SetInt("_MaterialCount", materialBuffer.count);
        compute.SetInt("_LightCount", lightBuffer.count);
        compute.SetVector("_AmbientColor", ambientColor);
        compute.SetInt("_ReflectionRayCount", reflectionRayCount);
        compute.SetInt("_MaxBounces", maxBounces);

        // Prepare output
        compute.SetTexture(kernel, "Result", renderTarget);

        // --- Camera data 
        float aspect = (float)renderTarget.width / renderTarget.height;

        // Build a projection for the RT aspect, not the camera’s current screen aspect
        Matrix4x4 proj = Matrix4x4.Perspective(renderCamera.fieldOfView, aspect, renderCamera.nearClipPlane, renderCamera.farClipPlane);

        Matrix4x4 invProj = proj.inverse;
        Matrix4x4 invView = renderCamera.cameraToWorldMatrix;

        compute.SetInts("_Resolution", renderTarget.width, renderTarget.height);
        compute.SetMatrix("_CamInvProj", invProj);
        compute.SetMatrix("_CamInvView", invView);
        compute.SetVector("_CamPos", renderCamera.transform.position);

        // Dispatch
        try
        {
            compute.GetKernelThreadGroupSizes(kernel, out uint sx, out uint sy, out uint sz);
            int groupsX = Mathf.CeilToInt(renderTarget.width / (float)sx);
            int groupsY = Mathf.CeilToInt(renderTarget.height / (float)sy);

            compute.Dispatch(kernel, groupsX, groupsY, 1);

            errorLogged = false;
        }
        catch
        {
            if (!errorLogged)
                Debug.LogError("Error in kernel!");
            errorLogged = true;
        }
    }
}
