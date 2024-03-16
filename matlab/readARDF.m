function [D] = readARDF(FN)
% INFORMATION & USAGE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% readARDF: Read data from binary ARDF Asylum Research Data File into a Matlab structure
%           Loads images, notes, and other information. DOES NOT load every force curve.
%           Use getARDFdata() to access individual force curves or lines of force curves.
%           Structure format based on Jakub Bialek's IBWread() on the Matlab File Exchange.
%
% Usage: D = readARDF('Foo.ardf') reads binary ARDF file Foo.ardf into struct D.
% Written by Matt Poss
% 2018-11-07
% INPUT ARGUMENTS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% FN:  File name (eg. 'Foo.ardf')
% CRC-32 used.
% Data used for checksum is entire entry minus the checksum.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
D.FileName = FN(1:end-5);
D.FileType = 'ARDF';
% Open file for reading
fid = fopen(FN,'r');
% =======================================
% ARDF: Asylum Research Data File
% Read file header
% =======================================
% Read file header & verify header type
[dumCRC, dumSize, lastType, dumMisc] = local_readARDFpointer(fid,0);
local_checkType(lastType, 'ARDF', fid);
% =======================================
% FTOC: File Table of Contents
% =======================================
% Read FTOC table
F.ftoc = local_readTOC(fid, -1, 'FTOC');
% =======================================
% TTOC: Text Table of Conents
% =======================================
% Read TTOC Table
loc_TTOC = F.ftoc.sizeTable + 16;
F.ttoc = local_readTOC(fid, loc_TTOC, 'TTOC');
% =======================================
% Read Main Notes
% =======================================
% Determine number of main notes to read
F.ttoc.numbNotes = size(F.ttoc.pntText,1);
% Assuming a single main note
% Read note
noteMain = local_readTEXT(fid, F.ttoc.pntText(1));
% Parse Note
%D.Notes = parseNotes( theNote );
% =======================================
% IMAG: Images
% =======================================
% Determine number of images to import
F.numbImag = size(F.ftoc.pntImag,1);
% Initialize data arrays
D.imageList = [];
D.y = [];
% Import all images
for n = 1:F.numbImag
	
    % Determine dynamic image structure name
    imagN = ['imag' num2str(n)];
    
	% * * * * * * * * * * * * *
	% IMAG header
	
    % Read IMAG Table
    F.(imagN) = local_readTOC(fid, F.ftoc.pntImag(n), 'IMAG');
	
	% * * * * * * * * * * * * *
	% IMAG-TTOC header
	
	% Reat IMAG-TTOC Table
    loc_IMAG_TTOC = F.ftoc.pntImag(n) + F.(imagN).sizeTable;
    F.(imagN).ttoc = local_readTOC(fid, loc_IMAG_TTOC, 'TTOC');
	
	% * * * * * * * * * * * * *
	% IDEF header
	
	% Navigate to IDEF within IMAG
    loc_IMAG_IDEF = F.ftoc.pntImag(n) + F.(imagN).sizeTable + F.(imagN).ttoc.sizeTable;
    F.(imagN).idef = local_readDEF(fid, loc_IMAG_IDEF, 'IDEF');
    
    % Add to imageList
    D.imageList = [D.imageList; F.(imagN).idef.imageTitle];
	
	% * * * * * * * * * * * * *
	% IBOX & IDAT image data
    
    % Read all IBOX/IDAT entries
    idat = local_readTOC(fid, -1, 'IBOX');
    
    % Write IDAT data to image array
    D.y = cat(3, D.y, idat.data);
    % Read closing IMAG header (GAMI), verify header type
    [dumCRC, dumSize, lastType, dumMisc] = local_readARDFpointer(fid,-1);
    local_checkType(lastType, 'GAMI', fid);
    
    % * * * * * * * * * * * * *
	% IMAG-TEXT 
    % Read the notes assocaited with each image
    
    % Determine number of loops to execute
    numbImagText = size(F.(imagN).ttoc.pntText,1);
    for r = 1:numbImagText
        
        % Read note
        theNote = local_readTEXT(fid, F.(imagN).ttoc.pntText(r));
        
        % Assign Note
        % We assume that there are max 3 notes for a given image
        % And that these three notes follow a predictable pattern
        if (numbImagText > 1) || (n == 1)
            switch r
                case 1
					noteThumb = theNote;
                    
                case 2
                    F.(imagN).note = parseNotes( theNote );
                    
                case 3
					noteQuick = theNote;
                    
            end % end switch
        else
            F.(imagN).note = parseNotes( theNote );
        end
    end % end read image notes for loop
    
end % end import image for loop
% =======================================
% Notes: Parse and save
% =======================================
if exist('noteQuick')
    theNote = [noteMain noteThumb noteQuick];
elseif exist('noteThumb')
    theNote = [noteMain noteThumb];
else
    theNote = noteMain;
end
D.Notes = parseNotes( theNote );
% =======================================
% VOLM: Force Curve Data
% =======================================
% Determine number of volumes
F.numbVolm = size(F.ftoc.pntVolm,1);
% Initialize data arrays
D.channelList = [];
% Import header data and pointers for each volume
for n = 1:F.numbVolm
    
    % Determine dynamic volume structure name
    volmN = ['volm' num2str(n)];
    
    % * * * * * * * * * * *
    % VOLM Header
    
    % Read all VOLM entries
    F.(volmN) = local_readTOC(fid, F.ftoc.pntVolm(n), 'VOLM');
    
    % * * * * * * * * * * *
    % VOLM-TTOC
    
    % Read all VOLM-TTOC entries
    loc_VOLM_TTOC = F.ftoc.pntVolm(n) + F.(volmN).sizeTable;
    F.(volmN).ttoc = local_readTOC(fid, loc_VOLM_TTOC, 'TTOC');
    
    % There do not appear to be any volume notes.
    
    % * * * * * * * * * * *
    % VOLM-VDEF
    
    % Read VDEF entry
    loc_VDEF_IMAG = F.ftoc.pntVolm(n) + F.(volmN).sizeTable + F.(volmN).ttoc.sizeTable;
    F.(volmN).vdef = local_readDEF(fid, loc_VDEF_IMAG, 'VDEF');
    
    % * * * * * * * * * * *
    % VOLM-VCHN & VOLM-XDEF
    
    % Initialize local arrays
    F.(volmN).vchn = [];
    F.(volmN).xdef = [];
    
    % We unfortunately don't know how many VCHN entries to expect
    done = 0;
    
    while done == 0
        % Read header
        [dumCRC, lastSize, lastType, dumMisc] = local_readARDFpointer(fid,-1);
        % Read data differently depending on data type
        switch lastType
            case 'VCHN'
                % Read 32 bytes of text
                textSize = 32;
                theChannel = transpose( fread(fid, textSize, '*char') );
                % Append to channelList
                F.(volmN).vchn = [F.(volmN).vchn; theChannel];
                % Read 32 dummy bytes
                remainingSize = lastSize - 16 - textSize;
                dum = fread(fid, remainingSize, '*char');
            case 'XDEF'
                % Read additional header parameters
                dum = fread(fid, 1, 'uint32');
                F.(volmN).xdef.sizeTable = fread(fid, 1, 'uint32');
                
                % Read text
                F.(volmN).xdef.text = transpose( fread(fid, F.(volmN).xdef.sizeTable, '*char') );
                
                % Read zero values
                dum = fread(fid, lastSize - 16 - 8 - F.(volmN).xdef.sizeTable, '*char');
                
                % Exit while loop
                done = 1;
                
            otherwise
                error(['ERROR: ' typeEntry ' not recognized!']);
        end % end switch type
    
    end % end while loop
    
    % Write channel list data to structure
    D.channelList = cat(3, D.channelList, F.(volmN).vchn);
    
    % * * * * * * * * * * *
    % VOLM-VTOC & VOLM-VOFF
    
    % Read Entire VTOC/VOFF Table
    F.(volmN).idx = local_readTOC(fid, -1, 'VTOC');
    
    % * * * * * * * * * * *
    % VOLM-MLOV
    
    % Verify that we have readed the end VOLM header, MLOV
    [dumCRC, lastSize, lastType, dumMisc] = local_readARDFpointer(fid,-1);
    local_checkType(lastType, 'MLOV', fid);
    
    % * * * * * * * * * * *
    % VOLM-VSET
    
    % Read first and last VSET point to get trace/retrace, up/down information
    % Alternatively every VSET can be read, but this takes more time, space
    % for r = 1:F.(volmN).vdef.lines
    for r = [1 F.(volmN).vdef.lines]
        
        % Determine dynamic field name
        vsetN = ['vset' num2str(r)];
        
        % Determine VSET address
        loc = F.(volmN).idx.linPointer(r);
        
        % If the data exists
		if loc ~= 0
			% Record VSET information
			F.(volmN).line.(vsetN) = local_readVSET(fid, loc);
            
			% Record Scan Up/Down information
			if F.(volmN).line.(vsetN).line ~= (r - 1)
				F.(volmN).scanDown = 1;
			else
				F.(volmN).scanDown = 0;
			end
			% Record Trace/Retrace Information
			if F.(volmN).line.(vsetN).point == 0
				F.(volmN).trace = 1;
			else
				F.(volmN).trace = 0;
			end
		end
        
    end % end for get point, line information
    
	% =======================================
	% Partial File Handling
	% 
	% Remove zero data from partial image files
	% Rewrite incorrect ScanDown note
	% =======================================
	
	% Find zero pointers to identify zero rows
    idxZero = find( F.(volmN).idx.linPointer == 0 );
    incMin = 1;
    incMax = 0;
	
	% If scanDown, then we need to flip the values of the idxZero array
	if F.(volmN).scanDown == 1
		idxZero = F.(volmN).vdef.lines - idxZero + 1;
        incMin = 0;
        incMax = 1;
	end	
	
end % end read all VOLM information
% Partial file handling continued
% Delete the zero rows
idxZeroMin = min(idxZero) - incMin;
idxZeroMax = max(idxZero) + incMax; % Remove an extra row just for good measure
D.y(:,idxZeroMin:idxZeroMax,:) = [];
% =======================================
% THMB: Thumbnails
% =======================================
% Do nothing with these. They are worth nothing to us. Nothing!
% =======================================
% User Notes
% =======================================
% Parse user notes from UserData.csv
% userFileName = 'UserData.csv';
% if exist(userFileName, 'file') == 2
% 	D.userNotes = parseUserData(D.FileName, userFileName);
% else
% 	error(['No ' userFileName ' file found!']);
% end
% Add additional notes
D.endNote.IsImage = '1';
% =======================================
% Detailed File Information
% =======================================
% Write file structure information to Matlab structure
D.FileStructure = F;
% Close file
fclose(fid);
end % end function
% @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
% @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
%
% Local Functions
%
% @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
% @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
% =======================================
% readTOC Function
% =======================================
function [toc] = local_readTOC(fid, address, type)
	
    % Define null pointer title
    nullCase = char([0 0 0 0]);
    
    if address ~= -1
        % Navigate to address
        fseek(fid, address, 'bof'); 
    end
    
    % Read TOC header, verify if correct type
    [dumCRC, lastSize, lastType, dumMisc] = local_readARDFpointer(fid,-1);
    local_checkType(lastType, type, fid);
    
    % Read remaining TOC header (assumes 32 byte header)
    toc.sizeTable = fread(fid,1,'uint64');
    toc.numbEntry = fread(fid,1,'uint32');
    toc.sizeEntry = fread(fid,1,'uint32');
    
    % Initialize pointer arrays
    switch toc.sizeEntry
        case 24
            % FTOC, IMAG, VOLM
            toc.pntImag = [];
            toc.pntVolm = [];
            toc.pntNext = [];
            toc.pntNset = [];
            toc.pntThmb = [];
        case 32
            % TTOC
            toc.idxText = [];
            toc.pntText = [];
        case 40 
            % VOFF
            toc.pntCounter = [];
            toc.linCounter = [];
            toc.linPointer = [];
        otherwise
            % IDAT
            toc.data = [];
            sizeRead = (toc.sizeEntry - 16) / 4;
    end % end switch
    
    % Initialize parameters for while loop
    done = 0;
    numbRead = 1;
    
    % Read TOC entries
    while (done == 0) && (numbRead <= toc.numbEntry)
        % Read entry header
        [dumCRC, dumSize, typeEntry, dumMisc] = local_readARDFpointer(fid,-1);
        % Read remainder of entry
        switch toc.sizeEntry
            case 24
                % FTOC, IMAG, VOLM
                lastPointer = fread(fid,1,'uint64');
            case 32
                % TTOC
                lastIndex = fread(fid,1,'uint64');
                lastPointer = fread(fid,1,'uint64');
            case 40
                % VOFF
                lastPntCount = fread(fid,1,'uint32');
                lastLinCount = fread(fid,1,'uint32');
                dum = fread(fid,1,'uint64');
                lastLinPoint = fread(fid,1,'uint64');
            otherwise
                % IDAT
                lastData = fread(fid, sizeRead, 'single');
        end % end switch
        % Record pointer depending on type of entry
        switch typeEntry
            case 'IMAG'
                toc.pntImag = [toc.pntImag; lastPointer];
            case 'VOLM'
                toc.pntVolm = [toc.pntVolm; lastPointer];
            case 'NEXT'
                toc.pntNext = [toc.pntNext; lastPointer];
            case 'NSET'
                toc.pntNset = [toc.pntNset; lastPointer];
            case 'THMB'
                toc.pntThmb = [toc.pntThmb; lastPointer];
            case 'TOFF'
                toc.idxText = [toc.idxText; lastIndex];
                toc.pntText = [toc.pntText; lastPointer];
            case 'IDAT'
                toc.data = [toc.data lastData];
            case 'VOFF'
                toc.pntCounter = [toc.pntCounter; lastPntCount];
                toc.linCounter = [toc.linCounter; lastLinCount];
                toc.linPointer = [toc.linPointer; lastLinPoint];
            case nullCase
                switch lastType
                    case 'IBOX'
                        toc.data = [toc.data lastData];
                    case 'VTOC'
                        toc.pntCounter = [toc.pntCounter; lastPntCount];
                        toc.linCounter = [toc.linCounter; lastLinCount];
                        toc.linPointer = [toc.linPointer; lastLinPoint];
                    otherwise
                        done = 1;
                end % end switch
            otherwise
                error(['ERROR: ' typeEntry ' not recognized!']);
        end % end switch
        
        % Increment entry counter
        numbRead = numbRead + 1;
        
    end % end while loop
end % end local_readTOC()
% =======================================
% readVSET Function
% =======================================
function [vset] = local_readVSET(fid, address)
    
    if address ~= -1
        % Navigate to address
        fseek(fid, address, 'bof'); 
    end
    
    % Read header, verify if correct type
    [dumCRC, lastSize, lastType, dumMisc] = local_readARDFpointer(fid,-1);
    local_checkType(lastType, 'VSET', fid);
    
	% Read VSET data
    vset.force = fread(fid, 1, 'uint32');
    vset.line = fread(fid, 1, 'uint32');
    vset.point = fread(fid, 1, 'uint32');
    dum = fread(fid, 1, 'uint32');
    vset.prev = fread(fid, 1, 'uint64');
    vset.next = fread(fid, 1, 'uint64');
    
end % end local_readVSET()
% =======================================
% readDEF Function
% =======================================
function [def] = local_readDEF(fid, address, type)
    
    if address ~= -1
        % Navigate to address
        fseek(fid, address, 'bof'); 
    end
    
    % Read DEF header, verify if correct type
    [dumCRC, sizeDEF, typeDEF, dumMisc] = local_readARDFpointer(fid,-1);
    local_checkType(typeDEF, type, fid);
	% Read points & lines
	def.points = fread(fid, 1, 'uint32');
	def.lines = fread(fid, 1, 'uint32');
	
    % Set bytes to skip
    switch typeDEF
        case 'IDEF'
            skip = 96;
        case 'VDEF'
            skip = 144;
    end % end switch
    
	% Read some bytes as dummy bytes
	dum = fread(fid, skip, '*char');
	
	% Read 32 bytes as text
    sizeText = 32;
	def.imageTitle = transpose( fread(fid, sizeText, '*char') );
    
	% Read remaining bytes as dummy bytes
    sizeHead = 16;
	remainingSize = sizeDEF - 8 - skip - sizeHead - sizeText;
	dum = fread(fid, remainingSize, '*char');
end % end local_readDEF()
% =======================================
% readTEXT Entries
% =======================================
function [txt] = local_readTEXT(fid, loc)
    
    % Navigate to the note section
	fseek(fid, loc, 'bof' );
    % Read the notes header, verify type
	[dumCRC, dumSize, lastType, dumMisc] = local_readARDFpointer(fid,-1);
    local_checkType(lastType, 'TEXT', fid);
    
	% Read the remainder of the header
	dumMisc = fread(fid,1,'uint32');
	sizeNote = fread(fid,1,'uint32');
	
	% Read the notes
	txt = transpose( fread(fid, sizeNote, '*char') );
end % end local_readTEXT()
% =======================================
% readARDFpointer Function
%
% Reads ARDF pointer. All pointers have similar 16 byte header.
% =======================================
function [ checkCRC32, sizeBytes, typePnt, miscNum ] = local_readARDFpointer( fid, address )
% Each pointer/header is 16 bytes
if address ~= -1
	% Navigate to address
	fseek(fid,address,'bof'); 
end
% Initialize typePnt
typePnt = zeros(1,4);
% Read pointer
checkCRC32 = fread(fid,1,'uint32');			% Read CRC-32 checksum
sizeBytes = fread(fid,1,'uint32');			% Read byte size of section
typePnt = transpose( fread(fid,4,'*char') );% Read 4-character pointer type
miscNum = fread(fid,1,'uint32');			% Read misc number
end % end local_local_readARDFpointer
% =======================================
% checkType Function
% 
% Verifies that pointer type is the expected type.
% =======================================
function [] = local_checkType(found, test, fid)
    if ~strcmp(found, test)
        error(['ERROR: No ' test ' here!  Found: ' found '  Location:' num2str( ftell(fid)-16 )]);
    end
end % end local_checkType

