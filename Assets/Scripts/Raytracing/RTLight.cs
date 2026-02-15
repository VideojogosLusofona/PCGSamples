using System.Runtime.InteropServices;
using UnityEngine;

[StructLayout(LayoutKind.Sequential)]
public struct GPULight
{
    public Vector3 position;
    public float   intensity;
    public Vector3 color;
    public float   range;
}

public class RTLight : MonoBehaviour
{
    [SerializeField] private Color color = Color.white;
    [SerializeField] private float intensity = 1.0f;
    [SerializeField] private float range = 1.0f;

    public GPULight GetGPULight()
    {
        return new GPULight
        {
            position = transform.position,
            intensity = intensity,
            color = new Vector3(color.r, color.g, color.b),
            range = range
        };
    }

    private void OnDrawGizmos()
    {
        Gizmos.color = color;
        Gizmos.DrawWireSphere(transform.position, range);
    }
}
