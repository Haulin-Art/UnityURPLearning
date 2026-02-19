using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Xml;
using UnityEngine;

public class Move : MonoBehaviour
{
    // Start is called before the first frame update

    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        if (Input.GetKey(KeyCode.W))
        {
            UnityEngine.Debug.Log("按下w");
            this.transform.position += new Vector3(0f,0f,0.01f);
        }
        if (Input.GetKey(KeyCode.S))
        {
            UnityEngine.Debug.Log("按下s");
            this.transform.position += new Vector3(0f, 0f, -0.01f);
        }
        if (Input.GetKey(KeyCode.A))
        {
            UnityEngine.Debug.Log("按下a");
            this.transform.position += new Vector3(-0.01f, 0f, 0f);
        }
        if (Input.GetKey(KeyCode.D))
        {
            UnityEngine.Debug.Log("按下d");
            this.transform.position += new Vector3(0.01f, 0f, 0f);
        }
    }
}
