using UnityEditor.ShaderGraph.Internal;
using UnityEngine;

public class RTPlane : RTPrimitive
{
    public override GPUPrimitive GetGPUPrimitive()
    {
        return new GPUPrimitive()
        {
            type = GPUPrimitiveType.Plane,
            material = 0,
            data0 = new Vector4(transform.up.x, transform.up.y, transform.up.z, -Vector3.Dot(transform.up, transform.position))
        };
    }

    private void OnDrawGizmos()
    {
        // Color from material (force alpha to 1 so it's always visible in gizmos)
        var c = material.albedo;
        c.a = 0.25f;
        Gizmos.color = c;

        // Apply plane transform so cube matches rotation
        Matrix4x4 oldMatrix = Gizmos.matrix;
        Gizmos.matrix = transform.localToWorldMatrix;

        // Thin cube: XZ = plane area, Y = thickness (normal is transform.up)
        float s = 5.0f;
        Gizmos.DrawCube(Vector3.zero, new Vector3(s, 0.02f, s));

        Gizmos.matrix = oldMatrix;

        // Draw normal
        Gizmos.color = Color.yellow;
        Gizmos.DrawLine(transform.position, transform.position + transform.up);
    }
}
