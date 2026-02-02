import numpy as np
from PIL import Image, ImageDraw
import requests
import json

# Create a simple test image with egg-like shapes
def create_test_image():
    # Create a white background
    img = Image.new('RGB', (800, 600), color='white')
    draw = ImageDraw.Draw(img)
    
    # Draw some egg-like ovals
    # Large egg (grade 0)
    draw.ellipse([100, 100, 250, 200], fill='lightgray', outline='black', width=2)
    
    # Medium egg (grade 2)
    draw.ellipse([300, 150, 400, 250], fill='lightgray', outline='black', width=2)
    
    # Small egg (grade 4)
    draw.ellipse([500, 200, 570, 270], fill='lightgray', outline='black', width=2)
    
    # Very small egg (grade 5)
    draw.ellipse([650, 250, 700, 300], fill='lightgray', outline='black', width=2)
    
    return img

# Test the detection
def test_detection():
    # Create test image
    test_img = create_test_image()
    test_img.save('test_eggs.png')
    
    # Send to API
    with open('test_eggs.png', 'rb') as f:
        files = {'file': ('test_eggs.png', f, 'image/png')}
        data = {'user_id': 1}
        
        try:
            response = requests.post('http://localhost:8000/detect', files=files, data=data)
            print(f"Status Code: {response.status_code}")
            print(f"Response: {response.json()}")
        except Exception as e:
            print(f"Error: {e}")

if __name__ == "__main__":
    test_detection()
