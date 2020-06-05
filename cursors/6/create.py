for i in range (7):
	with open ("azreticle" + str(i) + ".cursor", "w+") as f:
		f.write('{')
		f.write('\n"offset" : [15, 15],')
		f.write('\n"image" : "/cursors/6/azreticle.png:' + str(i) + '?scale=0.5"')
		f.write('\n}')