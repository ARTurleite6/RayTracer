import cv2
from skimage.metrics import structural_similarity as ssim
import argparse

# Parse arguments
parser = argparse.ArgumentParser(description="Compare two images using SSIM.")
parser.add_argument("imageA", help="First image path (reference)")
parser.add_argument("imageB", help="Second image path (test)")
args = parser.parse_args()

# Load both images
imageA = cv2.imread(args.imageA)
imageB = cv2.imread(args.imageB)

# Convert to grayscale for SSIM
imageA = cv2.cvtColor(imageA, cv2.COLOR_BGR2RGB)
imageB = cv2.cvtColor(imageB, cv2.COLOR_BGR2RGB)

# Compute SSIM
score, diff = ssim(imageA, imageB, full=True, channel_axis=2)
print(f"SSIM: {score:.6f}")

# Optionally visualize the difference map
diff = (diff * 255).astype("uint8")
cv2.imshow("Difference Map", diff)
cv2.waitKey(0)
