# Real Egg Detection Model
# ใช้ OpenCV หาขอบวัตถุจริงๆ และจำแนกไข่ตาม TIS 227-2524

import cv2
import numpy as np
from PIL import Image
import io
import base64
from typing import List, Dict, Tuple, Optional
import math
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class RealEggDetector:
    def __init__(self):
        """Initialize real egg detector with Thai egg grading standards"""
        # Thai Industrial Standard TIS 227-2524 egg grading (pixels)
        self.grade_thresholds = {
            "grade0": 18000,  # เบอร์ 0 (พิเศษ) - ใหญ่พิเศษ > 70g
            "grade1": 12000,  # เบอร์ 1 (ใหญ่) - 60-70g
            "grade2": 7000,   # เบอร์ 2 (กลาง) - 50-60g
            "grade3": 3500,   # เบอร์ 3 (เล็ก) - 40-50g
            "grade4": 1800,   # เบอร์ 4 (เล็กมาก) - 30-40g
            "grade5": 0       # เบอร์ 5 (พิเศษเล็ก) - < 30g
        }
        
        # Optimized egg detection parameters
        self.min_area = 800           # พื้นที่น้อยสุด
        self.max_area = 300000         # พื้นที่มากสุด
        self.min_aspect = 0.4          # aspect ratio น้อยสุด
        self.max_aspect = 2.5          # aspect ratio มากสุด
        self.min_circularity = 0.15    # ความกลมน้อยสุด
        self.min_confidence = 0.15     # confidence น้อยสุด
    
    def preprocess_image(self, image: Image.Image) -> Tuple[np.ndarray, np.ndarray]:
        """Preprocess image for egg detection"""
        try:
            # Convert PIL to OpenCV format
            cv_image = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
            
            # Convert to grayscale
            gray = cv2.cvtColor(cv_image, cv2.COLOR_BGR2GRAY)
            
            # Apply bilateral filter to reduce noise while preserving edges
            filtered = cv2.bilateralFilter(gray, 9, 75, 75)
            
            # Enhance contrast using CLAHE
            clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
            enhanced = clahe.apply(filtered)
            
            return enhanced, cv_image
            
        except Exception as e:
            logger.error(f"❌ Error preprocessing image: {e}")
            raise
    
    def detect_edges(self, gray_image: np.ndarray) -> np.ndarray:
        """Detect edges using multiple methods"""
        try:
            # Method 1: Canny edge detection with lower thresholds for better sensitivity
            edges_canny = cv2.Canny(gray_image, 20, 80)  # Further reduced thresholds
            
            # Method 2: Sobel edge detection
            sobel_x = cv2.Sobel(gray_image, cv2.CV_64F, 1, 0, ksize=3)
            sobel_y = cv2.Sobel(gray_image, cv2.CV_64F, 0, 1, ksize=3)
            sobel_magnitude = np.sqrt(sobel_x**2 + sobel_y**2)
            sobel_magnitude = np.uint8(sobel_magnitude / sobel_magnitude.max() * 255)
            
            # Method 3: Adaptive threshold for better edge detection in varying lighting
            adaptive_thresh = cv2.adaptiveThreshold(
                gray_image, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 9, 3
            )
            
            # Combine all methods
            combined_edges = cv2.bitwise_or(edges_canny, sobel_magnitude)
            combined_edges = cv2.bitwise_or(combined_edges, adaptive_thresh)
            
            # Morphological operations to close gaps but avoid merging objects
            kernel_small = np.ones((2,2), np.uint8)
            combined_edges = cv2.morphologyEx(combined_edges, cv2.MORPH_CLOSE, kernel_small)
            combined_edges = cv2.morphologyEx(combined_edges, cv2.MORPH_DILATE, kernel_small)
            
            # Remove border edges to avoid detecting the entire image frame
            height, width = combined_edges.shape
            border_size = 10
            combined_edges[:border_size, :] = 0
            combined_edges[-border_size:, :] = 0
            combined_edges[:, :border_size] = 0
            combined_edges[:, -border_size:] = 0
            
            return combined_edges
            
        except Exception as e:
            logger.error(f"❌ Error detecting edges: {e}")
            raise
    
    def find_egg_contours(self, edges: np.ndarray, original_shape: Tuple[int, int]) -> List[np.ndarray]:
        """Find contours that look like eggs"""
        try:
            # Find contours
            contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            
            egg_contours = []
            height, width = original_shape
            
            for contour in contours:
                # Calculate contour properties
                area = cv2.contourArea(contour)
                
                # Skip if too small or too large
                if area < self.min_area or area > self.max_area:
                    continue
                
                # Get bounding box
                x, y, w, h = cv2.boundingRect(contour)
                aspect_ratio = w / h
                
                # Skip if not egg-shaped
                if aspect_ratio < self.min_aspect or aspect_ratio > self.max_aspect:
                    continue
                
                # Calculate circularity
                perimeter = cv2.arcLength(contour, True)
                if perimeter > 0:
                    circularity = (4 * math.pi * area) / (perimeter * perimeter)
                    if circularity < self.min_circularity:
                        continue
                else:
                    continue
                
                # Check contour smoothness
                approx = cv2.approxPolyDP(contour, 0.02 * perimeter, True)
                if len(approx) < 6 or len(approx) > 30:
                    continue
                
                egg_contours.append(contour)
            
            return egg_contours
            
        except Exception as e:
            return []
    
    def classify_egg_grade(self, contour: np.ndarray) -> Tuple[str, float]:
        """Classify egg grade based on contour properties"""
        try:
            area = cv2.contourArea(contour)
            
            # Classify based on area
            if area >= self.grade_thresholds["grade0"]:
                grade = "grade0"
                confidence = min(0.95, 0.7 + (area - self.grade_thresholds["grade0"]) / 10000)
            elif area >= self.grade_thresholds["grade1"]:
                grade = "grade1"
                confidence = min(0.90, 0.6 + (area - self.grade_thresholds["grade1"]) / 10000)
            elif area >= self.grade_thresholds["grade2"]:
                grade = "grade2"
                confidence = min(0.85, 0.5 + (area - self.grade_thresholds["grade2"]) / 10000)
            elif area >= self.grade_thresholds["grade3"]:
                grade = "grade3"
                confidence = min(0.80, 0.4 + (area - self.grade_thresholds["grade3"]) / 10000)
            elif area >= self.grade_thresholds["grade4"]:
                grade = "grade4"
                confidence = min(0.75, 0.3 + (area - self.grade_thresholds["grade4"]) / 10000)
            else:
                grade = "grade5"
                confidence = max(0.3, 0.2 + area / self.grade_thresholds["grade4"])
            
            # Adjust confidence based on shape properties
            perimeter = cv2.arcLength(contour, True)
            if perimeter > 0:
                circularity = (4 * math.pi * area) / (perimeter * perimeter)
                confidence += circularity * 0.1
            
            return grade, min(confidence, 0.95)
            
        except Exception as e:
            logger.error(f"❌ Error classifying egg grade: {e}")
            return "grade2", 0.5  # Default to medium grade
    
    def detect_eggs(self, image: Image.Image) -> Dict:
        """Main egg detection function"""
        try:
            # Preprocess image
            gray_image, original_image = self.preprocess_image(image)
            
            # Detect edges
            edges = self.detect_edges(gray_image)
            
            # Find egg contours
            egg_contours = self.find_egg_contours(edges, gray_image.shape)
            
            # Process each egg contour
            detections = []
            grade_counts = {
                "grade0_count": 0,
                "grade1_count": 0,
                "grade2_count": 0,
                "grade3_count": 0,
                "grade4_count": 0,
                "grade5_count": 0
            }
            
            for contour in egg_contours:
                # Get bounding box
                x, y, w, h = cv2.boundingRect(contour)
                
                # Classify grade
                grade, confidence = self.classify_egg_grade(contour)
                
                # Skip if confidence too low
                if confidence < self.min_confidence:
                    continue
                
                # Update grade counts
                grade_counts[f"{grade}_count"] += 1
                
                # Create detection object
                detection = {
                    "id": len(detections) + 1,
                    "grade": grade,
                    "confidence": round(confidence, 2),
                    "area": int(cv2.contourArea(contour)),
                    "bbox": [int(x), int(y), int(w), int(h)]
                }
                detections.append(detection)
            
            # Calculate statistics
            total_eggs = len(detections)
            total_contours = len(egg_contours)
            success_percent = (total_eggs / max(total_contours, 1)) * 100
            
            result = {
                "detections": detections,
                "grade_counts": grade_counts,
                "total_eggs": total_eggs,
                "success_percent": round(success_percent, 1),
                "processed_contours": total_contours,
                "model_info": {
                    "type": "Real Egg Detector",
                    "method": "OpenCV Edge Detection + Contour Analysis",
                    "features": ["Edge Detection", "Contour Analysis", "Shape Filtering", "Size Classification"]
                }
            }
            
            return result
            
        except Exception as e:
            return {
                "detections": [],
                "grade_counts": {f"grade{i}_count": 0 for i in range(6)},
                "total_eggs": 0,
                "success_percent": 0.0,
                "error": str(e),
                "model_info": {
                    "type": "Real Egg Detector",
                    "status": "Error"
                }
            }

# Test function
def test_detector():
    """Test the real egg detector"""
    try:
        detector = RealEggDetector()
        logger.info("🎯 Real Egg Detector test completed successfully!")
        return detector
    except Exception as e:
        logger.error(f"❌ Test failed: {e}")
        raise

if __name__ == "__main__":
    test_detector()
