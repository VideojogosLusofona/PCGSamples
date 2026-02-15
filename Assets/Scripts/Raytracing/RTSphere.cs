using UnityEngine;

public class RTSphere : RTPrimitive
{
    [SerializeField] private float radius = 1.0f;

    public override GPUPrimitive GetGPUPrimitive()
    {
        return new GPUPrimitive
        {
            type = GPUPrimitiveType.Sphere,
            material = 0,
            data0 = new Vector4(transform.position.x, transform.position.y, transform.position.z, radius)
        };
    }

    private void OnDrawGizmos()
    {
        if (material.albedo.a < 1e-3)
        {
            Gizmos.color = new Color(material.albedo.r, material.albedo.g, material.albedo.b, 1.0f);
            Gizmos.DrawWireSphere(transform.position, radius);
        }
        else
        {
            Gizmos.color = material.albedo;
            Gizmos.DrawSphere(transform.position, radius);
        }
    }
}
