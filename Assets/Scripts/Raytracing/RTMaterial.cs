using System;
using System.Runtime.InteropServices;
using UnityEngine;

[Serializable]
[StructLayout(LayoutKind.Sequential)]
public struct RTMaterial
{
    public Color    albedo; 
    public float    emission;
    public float    roughness; 
    public float    metallic; 
    public float    ior;
    public Vector3  absorption; 
    public float    pad;
}
