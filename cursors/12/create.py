for i in range (13):
	with open ("azreticle" + str(i) + ".cursor", "w+") as f:
		f.write('{')
		f.write('\n"offset" : [15, 15],')
		f.write('\n"image" : "/cursors/12/azreticlerevolver.png:' + str(i) + '"')
		f.write('\n}')