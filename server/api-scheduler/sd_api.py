import json
import requests
import io
import base64
from PIL import Image, PngImagePlugin
import sd_s3

# webui_api_url
webui_api_url = "http://127.0.0.1:7860"

def process_sd_request(taskId, taskInfo):
    task = json.loads(taskInfo)
    res = call_simple_api(task["api"], task["payload"], f"sd/out/{taskId}")
    return res

def call_simple_api(api, payload, imagekey):
    imageList = []
    res = {"cnt":0, "images":[], "error": ""}
    cnt = 0
    try:
        # save png info only
        response = requests.post(url=f'{webui_api_url}{api}', json=payload)
        r = response.json()
        for i in r['images']:
            imageBody = base64.b64decode(i.split(",",1)[0])
            cnt = cnt + 1
            imagePath = f"{imagekey}-{cnt}.png"
            uri = sd_s3.put_object_to_s3(imagePath, imageBody, 'image/png')
            imageList.append(uri)

            #image = Image.open(io.BytesIO(base64.b64decode(i.split(",",1)[0])))
            #png_payload = {
            #    "image": "data:image/png;base64," + i
            #}
            #response2 = requests.post(url=f'{webui_api_url}/sdapi/v1/png-info', json=png_payload)
            #pnginfo = PngImagePlugin.PngInfo()
            #pnginfo.add_text("parameters", response2.json().get("info"))
            #image.save('output.png', pnginfo=pnginfo)
        res["cnt"] = cnt
        res["images"] = imageList
    except Exception as e:
        res["error"] = f"{e}"

    return res

if __name__ == "__main__":
    api = '/sdapi/v1/txt2img'
    payload = {
        "prompt": "puppy dog",
        "steps": 5
    }
    imageKey = 'test/run_sd_api'

    # in local machine test mode change webui api url
    webui_api_url = "http://ec2-13-250-5-36.ap-southeast-1.compute.amazonaws.com:7860"
    res = process_sd_request(api, payload, imageKey)
    print(res)