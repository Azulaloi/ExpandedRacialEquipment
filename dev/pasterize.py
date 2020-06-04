import sys
import pyperclip

def pasterize(filename):
	f = open(filename, "r")
	list = [line.rstrip('\n') for line in f]
	f.close()

	joined = ''.join(list)
	# joined.replace(" ", "")

	pyperclip.copy(joined)
	
if __name__== "__main__":
    pasterize(str(sys.argv[1]))