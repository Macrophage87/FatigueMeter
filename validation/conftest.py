import os
import sys

# make the `fatiguemeter` package importable when pytest runs from anywhere
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))
