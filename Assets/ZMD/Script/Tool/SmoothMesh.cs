using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;

// 完整讲解：https://zhuanlan.zhihu.com/p/695612604
public class SmoothMesh : EditorWindow {
	// Statue Vals
	private Mesh mesh;

	private void OnGUI() {
		Transform selectedObject = Selection.activeGameObject.transform;

		if( selectedObject == null ) {
			EditorGUILayout.LabelField( "请选择一个物体" );
			return;
		}

		// Get Mesh
		bool useSkinMesh = false;
		var meshFilter = selectedObject.GetComponent<MeshFilter>();
		var skinnedMeshRenderer = selectedObject.GetComponent<SkinnedMeshRenderer>();
		if( meshFilter != null ) {
			useSkinMesh = false;
			mesh = meshFilter.sharedMesh;
		} else if( skinnedMeshRenderer != null ) {
			useSkinMesh = true;
			mesh = skinnedMeshRenderer.sharedMesh;
		} else {
			EditorGUILayout.LabelField( "选择一个带mesh的物体" );
			return;
		}

		//绘制 Gui 
		EditorGUILayout.BeginVertical(); //开启垂直视图绘制
		EditorGUILayout.LabelField( "选择的物体为: " + selectedObject.name ); //文本
		EditorGUILayout.LabelField( "当前选择的物体的网格为：" + mesh.name );
		if( GUILayout.Button( "另存并替换网格" ) ) {
			mesh = exportMesh( mesh, "Assets/ZMD/SmoothMesh" );
			if( useSkinMesh ) {
				skinnedMeshRenderer.sharedMesh = mesh;
			} else {
				meshFilter.sharedMesh = mesh;
			}
		}


		if( GUILayout.Button( "写入切线空间平滑法线到顶点色" ) ) {
			var normals = GenerateSmoothNormals( mesh ); //获取上一步的平滑后法线（切线空间）	
			Color[] vertCols = new Color[normals.Length];
			vertCols = vertCols.Select( ( col, ind ) => new Color( normals[ind].x, normals[ind].y, normals[ind].z, 1.0f ) ).ToArray(); //将法线每一项的向量转化为颜色
			mesh.colors =vertCols; //设置网格顶点色	
		}

		EditorGUILayout.EndVertical();
	}

	[MenuItem( "Tools/Smooth Normal" )]
	private static void OpenWindows() {
		GetWindow<SmoothMesh>( false, "smooth normal", true ).Show();
	}


	private static Vector3[] GenerateSmoothNormals( Mesh srcMesh ) {
		Vector3[] verticies = srcMesh.vertices;
		Vector3[] normals = srcMesh.normals;
		Vector3[] smoothNormals = normals;

		// 将同一个顶点的所有法线存到一个列表中 <顶点，所有面拐法线>
		var normalDict = new Dictionary<Vector3, List<Vector3>>();
		for( int i = 0; i < verticies.Length; i++ ) {
			if( !normalDict.ContainsKey( verticies[i] ) ) {
				normalDict.Add( verticies[i], new List<Vector3>() );
			}
			normalDict[verticies[i]].Add( normals[i] );
		}

		// 计算同一个顶点的所有法线的平均值 <顶点，平均法线>
		var averageNormalsDict = new Dictionary<Vector3, Vector3>();
		foreach( var pair in normalDict ) {
			Vector3 averageNormal = pair.Value.Aggregate( Vector3.zero, ( current, n ) => current + n );
			averageNormal /= pair.Value.Count;
			averageNormalsDict.Add( pair.Key, averageNormal.normalized );
		}

		for( int i = 0; i < smoothNormals.Length; i++ ) {
			smoothNormals[i] = averageNormalsDict[verticies[i]]; //对每个顶点查找平均法线
		}

        //return smoothNormals;
		return GetTangentSpaceNormal( smoothNormals, srcMesh );
	}

	private static Vector3[] GetTangentSpaceNormal( Vector3[] smoothedNormals, Mesh srcMesh ) {
		Vector3[] normals = srcMesh.normals;
		Vector4[] tangents = srcMesh.tangents;

		Vector3[] smoothedNormalsTs = new Vector3[smoothedNormals.Length];

		for( int i = 0; i < smoothedNormalsTs.Length; i++ ) {
			Vector3 normal = normals[i];
			Vector4 tangent = tangents[i];

			Vector3 tangentV3 = new Vector3( tangent.x, tangent.y, tangent.z );

			var bitangent = Vector3.Cross( normal, tangentV3 ) * tangent.w;
			bitangent = bitangent.normalized;

			var TBN = new Matrix4x4( tangentV3, bitangent, normal, Vector4.zero );
			TBN = TBN.transpose;

			var smoothedNormalTs = TBN.MultiplyVector( smoothedNormals[i] ).normalized;

			smoothedNormalsTs[i] = smoothedNormalTs;
		}

		return smoothedNormalsTs;
	}

	public static void Copy( Mesh dest, Mesh src ) {
		dest.Clear();

		// 复制顶点、UV、法线、切线、权重、颜色、颜色32、骨骼、形态键、子网格、名称
		dest.vertices = src.vertices;
		List<Vector4> uvs = new List<Vector4>();
		for( int i = 0; i < 8; i++ ) {
			src.GetUVs( i, uvs );
			dest.SetUVs( i, uvs );
		}
		dest.normals = src.normals;
		dest.tangents = src.tangents;
		dest.boneWeights = src.boneWeights;
		dest.colors = src.colors;
		dest.colors32 = src.colors32;
		dest.bindposes = src.bindposes;

		// 形态键的格式是这样，具体内容先不深究了
		Vector3[] deltaVertices = new Vector3[src.vertexCount];
		Vector3[] deltaNormals = new Vector3[src.vertexCount];
		Vector3[] deltaTangents = new Vector3[src.vertexCount];
		for( int shapeIndex = 0; shapeIndex < src.blendShapeCount; shapeIndex++ ) {
			string shapeName = src.GetBlendShapeName( shapeIndex );
			int frameCount = src.GetBlendShapeFrameCount( shapeIndex );
			for( int frameIndex = 0; frameIndex < frameCount; frameIndex++ ) {
				float frameWeight = src.GetBlendShapeFrameWeight( shapeIndex, frameIndex );
				src.GetBlendShapeFrameVertices( shapeIndex, frameIndex, deltaVertices, deltaNormals, deltaTangents );
				dest.AddBlendShapeFrame( shapeName, frameWeight, deltaVertices, deltaNormals, deltaTangents );
			}
		}

		dest.subMeshCount = src.subMeshCount;
		for( int i = 0; i < src.subMeshCount; i++ )
			dest.SetIndices( src.GetIndices( i ), src.GetTopology( i ), i );

		dest.name = src.name;
	}

	public static Mesh exportMesh( Mesh mesh, string path ) {
		Mesh mesh2 = new Mesh();
		Copy( mesh2, mesh );
		mesh2.name = mesh2.name + "_SMNormal";
		AssetDatabase.CreateAsset( mesh2, path + mesh2.name + ".asset" );
		AssetDatabase.SaveAssets();
		AssetDatabase.Refresh();
		return mesh2;
	}
}