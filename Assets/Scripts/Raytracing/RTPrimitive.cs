using NaughtyAttributes;
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;

public enum GPUPrimitiveType
{
    Sphere = 0,
    Plane = 1, DualSidedPlane = 2, 
    Union = 3, Intersect = 4, Subtract = 5,
    SmoothUnion = 6, SmoothIntersect = 7, SmoothSubtract = 8,
    Repeat = 9,
}

[StructLayout(LayoutKind.Sequential)]
public struct GPUPrimitive
{
    public int      type;       // 0 = sphere, 1 = plane
    public int      material;
    public int      arg1, arg2; // Operands for boolean ops
    public Vector4  data0;      // sphere: (cx,cy,cz,r)   plane: (nx,ny,nz,d)
}

public abstract class RTPrimitive : MonoBehaviour
{
    [SerializeField, HideIf(nameof(isArg))] protected RTMaterial material;

    public bool isArg => ((transform.parent != null) && (transform.parent.GetComponent<RTBoolean>() != null));

    public abstract int GatherPrimitive(List<GPUPrimitive> primitives);

    public RTMaterial GetMaterial()
    {
        return material;
    }
}
