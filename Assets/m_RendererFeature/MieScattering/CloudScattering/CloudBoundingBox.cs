using UnityEngine;

[ExecuteInEditMode]
public class CloudBoundingBox : MonoBehaviour
{
    [Header("Cloud Settings")]
    public float cloudBottomHeight = 1000.0f;
    public float cloudTopHeight = 3000.0f;
    
    [Header("Visualization")]
    public bool showBoundingBox = true;
    public Color bottomSphereColor = new Color(0.5f, 0.5f, 1.0f, 0.2f);
    public Color topSphereColor = new Color(0.5f, 0.5f, 1.0f, 0.2f);
    
    private GameObject bottomSphere;
    private GameObject topSphere;
    
    private void OnEnable()
    {
        CreateBoundingSpheres();
    }
    
    private void OnDisable()
    {
        DestroyBoundingSpheres();
    }
    
    private void Update()
    {
        if (showBoundingBox)
        {
            if (bottomSphere == null || topSphere == null)
            {
                CreateBoundingSpheres();
            }
            
            // 更新球体大小
            bottomSphere.transform.localScale = new Vector3(cloudBottomHeight * 2, cloudBottomHeight * 2, cloudBottomHeight * 2);
            topSphere.transform.localScale = new Vector3(cloudTopHeight * 2, cloudTopHeight * 2, cloudTopHeight * 2);
            
            // 更新球体颜色
            UpdateSphereMaterial(bottomSphere, bottomSphereColor);
            UpdateSphereMaterial(topSphere, topSphereColor);
        }
        else
        {
            DestroyBoundingSpheres();
        }
    }
    
    private void CreateBoundingSpheres()
    {
        // 销毁已存在的球体
        DestroyBoundingSpheres();
        
        // 创建云底球体
        bottomSphere = CreateSphere("CloudBottomSphere", cloudBottomHeight, bottomSphereColor);
        
        // 创建云顶球体
        topSphere = CreateSphere("CloudTopSphere", cloudTopHeight, topSphereColor);
    }
    
    private GameObject CreateSphere(string name, float radius, Color color)
    {
        GameObject sphere = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        sphere.name = name;
        sphere.transform.parent = transform;
        sphere.transform.localPosition = Vector3.zero;
        sphere.transform.localScale = new Vector3(radius * 2, radius * 2, radius * 2);
        
        // 创建透明材质
        Material material = new Material(Shader.Find("Universal Render Pipeline/Unlit"));
        material.color = color;
        material.SetFloat("_Surface", 1); // 透明模式
        material.SetFloat("_Blend", 1);   // 混合模式
        material.renderQueue = 3000;       // 透明队列
        material.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.SrcAlpha);
        material.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
        material.SetInt("_ZWrite", 0);    // 关闭深度写入
        material.DisableKeyword("_ALPHATEST_ON");
        material.EnableKeyword("_ALPHABLEND_ON");
        material.DisableKeyword("_ALPHAPREMULTIPLY_ON");
        
        sphere.GetComponent<MeshRenderer>().material = material;
        
        // 禁用碰撞器
        DestroyImmediate(sphere.GetComponent<SphereCollider>());
        
        return sphere;
    }
    
    private void UpdateSphereMaterial(GameObject sphere, Color color)
    {
        if (sphere != null && sphere.GetComponent<MeshRenderer>() != null)
        {
            sphere.GetComponent<MeshRenderer>().material.color = color;
        }
    }
    
    private void DestroyBoundingSpheres()
    {
        if (bottomSphere != null)
        {
            DestroyImmediate(bottomSphere);
            bottomSphere = null;
        }
        
        if (topSphere != null)
        {
            DestroyImmediate(topSphere);
            topSphere = null;
        }
    }
    
    // 绘制Gizmos
    private void OnDrawGizmos()
    {
        if (showBoundingBox)
        {
            Gizmos.color = bottomSphereColor;
            Gizmos.DrawWireSphere(transform.position, cloudBottomHeight);
            
            Gizmos.color = topSphereColor;
            Gizmos.DrawWireSphere(transform.position, cloudTopHeight);
        }
    }
}