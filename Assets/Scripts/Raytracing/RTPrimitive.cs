using System;
using System.Runtime.InteropServices;
using UnityEngine;

public enum GPUPrimitiveType : int
{
    Sphere = 0,
    Plane = 1
}

[StructLayout(LayoutKind.Sequential)]
public struct GPUPrimitive
{
    public GPUPrimitiveType type;      // 0 = sphere, 1 = plane
    public int              material;
    public Vector2          pad0;      // padding to 16 bytes

    public Vector4          data0;     // sphere: (cx,cy,cz,r)   plane: (nx,ny,nz,d)
}

public abstract class RTPrimitive : MonoBehaviour
{
    [SerializeField] protected RTMaterial material;

    public abstract GPUPrimitive GetGPUPrimitive();

    public RTMaterial GetMaterial()
    {
        return material;
    }
}
