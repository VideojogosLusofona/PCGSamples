using System.Runtime.InteropServices;
using UnityEngine;

[StructLayout(LayoutKind.Sequential)]
public struct GPULight
{
    public Vector3 position;
    public float   intensity;
    public Vector3 color;
    public float   range;
    public float   size;
}

public class RTLight : MonoBehaviour
{
    [SerializeField] private Color color = Color.white;
    [SerializeField, Min(0.0f)] private float intensity = 1.0f;
    [SerializeField, Min(0.0f)] private float range = 1.0f;
    [SerializeField, Min(0.0f)] private float lightSize = 0.1f;

    public GPULight GetGPULight()
    {
        return new GPULight
        {
            position = transform.position,
            intensity = intensity,
            color = new Vector3(color.r, color.g, color.b),
            range = range,
            size = lightSize
        };
    }

    private void OnDrawGizmos()
    {
        Gizmos.color = color;
        Gizmos.DrawSphere(transform.position, lightSize);
        Gizmos.DrawWireSphere(transform.position, range);
    }
}
