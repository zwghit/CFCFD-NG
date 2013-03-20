import sys

# Some useful functions

def remove_spaces( tk ):
    return tk.replace(" ","")

def remove_braces( tk ):
    return tk.replace("(","").replace(")","").replace("[","").replace("]","")

# level classes

class IonizationLimit:
    def __init__(self,label,E):
        self.label = label
        self.E = E

class GroupedLevel:
    def __init__(self, level_tks ):
        # extract config and term info
        tks = level_tks[0]
        self.config = remove_spaces(tks[0])
        self.term = remove_spaces(tks[1])
        # get the g and E values for each individual level
        self.g_list = []
        self.E_list = []
        for tks in level_tks:
            self.g_list.append( int(remove_spaces(tks[2]))*2+1 )
            self.E_list.append( float(remove_braces(remove_spaces(tks[3]))) )
        self.nlevels = len(self.g_list)
        # create multiplet level data
        self.g = sum( self.g_list )
        tmp = 0.0
        for i in range(self.nlevels):
            tmp += self.g_list[i] * self.E_list[i]
        self.E = tmp / self.g

class LevelData:
    def __init__(self):
        self.levels = []
        self.ionization_limits = []

    def make_levels_from_raw_data( self, raw_level_data ):
        count = 0
        for level_tks in raw_level_data:
            self.levels.append( GroupedLevel( level_tks ) )
            count += self.levels[-1].nlevels
        print "created %d multiplet levels, totally %d individual levels" % ( len(self.levels), count )

# line classes

class IndividualLine:
    def __init__(self, config_i, config_k, term_i, term_k, line_tks ):
        self.config_i = config_i
        self.config_k = config_k
        self.term_i = term_i
        self.term_k = term_k
        # get the parameters for this line
        tmp = line_tks[3].split("-")
        self.Ei = float( remove_spaces(tmp[0]) )
        self.Ek = float( remove_spaces(tmp[1]) )
        tmp = line_tks[4].split("-")
        self.gi = int( remove_spaces(tmp[0]) )
        self.gk = int( remove_spaces(tmp[1]) )
        self.A = float( remove_spaces(line_tks[5]) )
        self.acc = remove_spaces( line_tks[6] )
        self.type = remove_spaces( line_tks[7] )

class MultipletLine:
    def __init__(self, prev_line, grouped_line_tks ):
        line_tks = grouped_line_tks[0]
        # extract config and term info
        tks = line_tks[1].split("-")
        if remove_spaces(line_tks[1])=="":
            # use prev line config data
            self.config_i = prev_line.config_i
            self.config_k = prev_line.config_k
        else:
            self.config_i = remove_spaces(tks[0])
            self.config_k = remove_spaces(tks[1])
        tks = line_tks[2].split("-")
        self.term_i = remove_spaces(tks[0])
        self.term_k = remove_spaces(tks[1])
        # check for multiplet data
        tmp = line_tks[3]
        if remove_spaces(tmp)=="":
            has_multiplet_data = False
        else:
            has_multiplet_data = True
            tks = line_tks[3].split("-")
            self.Ei = float( remove_spaces( tks[0] ) )
            self.Ek = float( remove_spaces( tks[1] ) )
            tks = line_tks[4].split("-")
            self.gi = int( remove_spaces( tks[0] ) )
            self.gk = int( remove_spaces( tks[1] ) )
            tk = line_tks[5]
            self.A = float( remove_spaces( tk ) )
            tk = line_tks[6]
            self.acc = remove_spaces( tk )
            tk = line_tks[7]
            self.type = remove_spaces( tk )
        # create the individual lines
        self.lines = []
        for line_tks in grouped_line_tks[2:-1]:
            self.lines.append( IndividualLine( self.config_i, self.config_k, self.term_i, self.term_k, line_tks ) )
        self.nlines = len(self.lines)
        if not has_multiplet_data:
            # calculate multiplet data ourselves
	    icopies = []; kcopies = []
	    for iml in range(len(self.lines)):
	        # find unique levels
	        for jml in range(iml+1,len(self.lines)):
		    if self.lines[iml].Ei==self.lines[jml].Ei and iml not in icopies:
		        icopies.append(jml)
		    if self.lines[iml].Ek==self.lines[jml].Ek and iml not in kcopies:
		        kcopies.append(jml)
	    # i and kcopies should hold list of repeated states
            self.Ei = 0; self.Ek = 0
            self.gi = 0; self.gk = 0
            self.A = 0
            for i,line in enumerate(self.lines):
                if i not in icopies:
                    self.gi += line.gi
                    self.Ei += line.gi*line.Ei
                if i not in kcopies:
                    self.gk += line.gk
                    self.Ek += line.gk*line.Ek
                self.A += line.gk*line.A
            self.Ei /= self.gi
            self.Ek /= self.gk
            self.A /= self.gk

class LineData:
    def __init__(self):
        self.lines = []
        self.n_multiplet_lines = 0
        self.n_individual_lines = 0 

    def make_lines_from_raw_data( self, raw_line_data ):
        count = 0
        prev_line = None
        for line_tks in raw_line_data:
            self.lines.append( MultipletLine( prev_line, line_tks ) )
            prev_line = self.lines[-1]
            count += prev_line.nlines
        self.n_multiplet_lines = len(self.lines)
        self.n_individual_lines = count
        print "created %d multiplet lines, totally %d individual lines" % ( self.n_multiplet_lines, self.n_individual_lines )


# read functions

def read_level_file( filename ):
    # read in the file
    infile = open(filename, 'r')
    lines = infile.readlines()
    infile.close()

    # check the header
    tks = remove_spaces(lines[1]).split("|")
    if tks[0]!="Configuration" or tks[1]!="Term" or tks[2]!="J" or tks[3]!="Level":
        print "The header in file %s does not appear to match the expected format:" % filename
        print "Configuration          | Term   |   J |                 Level    |"
        sys.exit()

    # read in levels, one line at a time
    level_data = LevelData()
    raw_level_data = []
    level_tks = [] 
    for line in lines[3:]:
        tks = line.split("|")
        if len(tks)<=1: continue
        if remove_spaces(tks[1])=="Limit":
            E_limit = float(remove_braces(tks[3]))
            print "Encountered %s ionization limit at %f" % ( tks[0], E_limit )
            level_data.ionization_limits.append( IonizationLimit( tks[0], E_limit ) )
            continue
        if remove_spaces(tks[3])=="" or tks[0]=="-----------------------":
            if len(level_tks)>0:
                # print "level_data = ", level_data
                raw_level_data.append( level_tks )
            level_tks = []
            continue
        else:
            level_tks.append( tks )

    # convert the tks to data
    level_data.make_levels_from_raw_data( raw_level_data )

    return level_data

def read_line_file( filename ):
    # read in the file
    infile = open(filename, 'r')
    lines = infile.readlines()
    infile.close()

    # check the header
    tks = remove_spaces(lines[1]).split("|")
    if tks[0]!="Mult." or tks[1]!="Configurations" or tks[2]!="Terms":
        print "The header in file %s does not appear to match the expected format:" % filename
        print "Mult. |           Configurations                 |     Terms    |       Ei           Ek       | gi   gk |    Aki    | Acc. |Type|"
        sys.exit()
        
    # read in lines, one block at a time
    raw_line_data = []
    line_tks = []
    for line in lines[5:]:
        tks = line.split("|")
        if len(tks)<=1: continue
        if remove_spaces(tks[0])!="":
            if len(line_tks)>0:
                raw_line_data.append( line_tks )
            line_tks = [ tks ]
            continue
        else:
            line_tks.append( tks )

    # convert the tks to data
    line_data = LineData()
    line_data.make_lines_from_raw_data( raw_line_data )

    return line_data