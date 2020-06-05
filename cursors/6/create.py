for i in range (7):
	with open ("azreticle" + str(i) + ".cursor", "w+") as f:
		f.write('{')
		f.write('\n"offset" : [30, 30],')
		f.write('\n"image" : "/cursors/6/azreticle.png:' + str(i) + '"')
		f.write('\n}')