using System.Collections.Generic;
using UnityEngine;

public class RTBoolean : RTPrimitive
{
    public enum Operation { Union, Intersection, Difference };

    [SerializeField] 
    private Operation operation;
    [SerializeField, Min(0.0f)] 
    private float smoothness;

    private void OnDrawGizmos()
    {
        int argCount = 0;
        foreach (Transform t in transform)
        {
            if (t.GetComponent<RTPrimitive>() != null) argCount++;
        }

        if (argCount < 2) Debug.LogWarning("Missing arguments for boolean operation!");
        else if (argCount > 2) Debug.LogWarning("Too many arguments for boolean operation!");
    }

    public override int GatherPrimitive(List<GPUPrimitive> primitives)
    {
        // Iterate operands and add them
        int arg1 = -1;
        int arg2 = -1;
        foreach (Transform t in transform)
        {
            var argPrimitive = t.GetComponent<RTPrimitive>();
            if (argPrimitive != null)
            {
                var idx = argPrimitive.GatherPrimitive(primitives);
                var r = primitives[idx];
                r.type = r.type | unchecked((int)0x80000000);
                primitives[idx] = r;
                if (arg1 == -1) arg1 = idx;
                else arg2 = idx;
            }
        }

        var tmp = new GPUPrimitive()
        {
            type = OperationToPrimitive(),
            arg1 = arg1,
            arg2 = arg2,
            data0 = new Vector4(smoothness, 0.0f, 0.0f, 0.0f)
        };


        primitives.Add(tmp);

        return primitives.Count - 1;
    }

    int OperationToPrimitive()
    {
        if (smoothness > 0.0f)
        {
            switch (operation)
            {
                case Operation.Union: return (int)GPUPrimitiveType.SmoothUnion;
                case Operation.Intersection: return (int)GPUPrimitiveType.SmoothIntersect;
                case Operation.Difference: return (int)GPUPrimitiveType.SmoothSubtract;
            }
        }
        else
        {
            switch (operation)
            {
                case Operation.Union: return (int)GPUPrimitiveType.Union;
                case Operation.Intersection: return (int)GPUPrimitiveType.Intersect;
                case Operation.Difference: return (int)GPUPrimitiveType.Subtract;
            }
        }
        return (int)GPUPrimitiveType.Union;
    }
}
