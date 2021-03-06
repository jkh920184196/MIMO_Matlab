%% *************************************************************************************************
clear all
close all

%start timer
tic

%Parameters set for a Speaker with 12 channels and a Zylia microphone (19 ch)
Mic           = 19;           %Number of microphones
Spk           = 12;           %Number of loudspeakers


selpath = uigetdir;
DirName = selpath;
N             = 48000*0.5;     %Lenght of each IR in the MIMO matrix     
SweepLength   = 10;            %Length of used sweep [s]
SilenceLength = 4;             %Length of silence after each sweep [s]

[PinkEqFile,Fs] = audioread('New-STI-step2.wav');

%Load inverse sweep data
[InvSweep,Fs] = audioread('InvSweep_20_20KHz_10.WAV');
DeltaSample   = (SweepLength+SilenceLength)*Fs;

% Store the paths of files which produce an error
problematicFiles = "";

%% *************************************************************************************************
%  Loading SWEEP recordings and IR deconvolution
% **************************************************************************************************
addpath( './Lib' )                                                          % add to path the library with needed common files

disp('Loading Sweep recording and IR deconvolution...')

%List files in folder
dinfo = dir(fullfile(DirName, '**\*.w64'));
% filelist = fullfile(DirName, '**\*.w64');
% for j = 1:length(dinfo)
%     disp(dinfo(j).folder);
% end
dinfo([dinfo.isdir]) = [];     %get rid of all directories including . and ..
nfiles = length(dinfo);


progressbar('Files', 'Microphones', 'Beamforming', 'Background Noise');


% Iterates through all files in the target folder, based on their extension
for j = 1 : nfiles
  
      % Puts output to the output subfolder, and creates it if necessary
    outDir = strcat(dinfo(j).folder, '/output');
    if ~exist(outDir, 'dir')
        mkdir(outDir)
        fprintf('Created folder: %s\n', outDir);
    end  
    
  filename = fullfile(dinfo(j).folder, dinfo(j).name);
  disp("File name = " + filename);
  fprintf("Processing file %d out of %d\n", j, nfiles);
  [filepath,name,ext] = fileparts(filename);
  disp("File path = " + filepath);
  [~, FolderName] = fileparts(DirName);
  outname = strcat(filepath, "/output/", FolderName, name);
  fprintf("Extension = %s\n", ext);
  
%   if and((strcmp(ext, '.w64')==0),(strcmp(ext, '.wav')==0))
%      fprintf("Wrong extension!\n");
%      continue;
%   end
  
  % Define the MIMO IR matrix (Speakers x Microphones x N_Samples)
  MIMOIR = zeros(Spk,Mic,N);
  
  %Read WAV file containing a sequence of sweeps
  % RecSweep = recorded sweep
  % Fs = sampling frequency (48000)
  % TODO: replace all instances of 48000 with a consistent variable
  disp(filename);
  [RecSweep,Fs] = audioread(filename);

    % perform deconvolution
    for m = 1:1:Mic
%
         
        fprintf('Mic: (%d/%d)\n',m,Mic);
        %Deconvolve each ir channel
        convRes = fd_conv( RecSweep(:,m), InvSweep );
        % stores in convRes the convolution of the current mic channel of
        % the recorded sweep with the inverse sweep
        % so convRes = convolved response

        %Show the first trimmed IR to check cut
        if (m==1)

           %Find the largest peak, and its index
           [maxPeak, maxIndex] =  max(convRes);

           %Set the trim point at the first peak
           TrimSample = maxIndex-0.1*N;
           figureTitle = strcat('Time slicing ',filename);
           figure('Name',figureTitle,'NumberTitle','off');
           subplot(2,1,1)
           plot(convRes); 

           hold on;
           title('Before the time slicing');
           % Draw the trim point
           plot([maxIndex maxIndex],[-100 100],'ro');
           plot([TrimSample TrimSample+N],[0 0],'bo');
           for s = 1:Spk
               plot([TrimSample+DeltaSample*(s-1) TrimSample+N-1+DeltaSample*(s-1)],[0 0], 'go');
           end
           hold off;

           % I've already forgotten the specifics, but subplot does the
           % figure layout
           subplot(2,1,2)
           
           % Stores the trimmed IR
           try
                convResTrim = convRes(TrimSample:TrimSample+N); % .* win;
                plot(convResTrim);
                title('After the time slicing');
           catch
               disp("Wrong number of sweeps!");
               problematicFiles = strcat(problematicFiles, filename, ", Wrong number of sweeps", "\n");
           end
          
           
           beep
        end
       
        for s = 1:Spk % iterate over the loudspeakers
            % slice the multiple sequential IRs into separate cells of MIMO matrix
            try
                MIMOIR(s,m,:) = convRes(TrimSample+DeltaSample*(s-1):TrimSample+N-1+DeltaSample*(s-1));
            catch
                % Error in trimming procedure
                problematicFiles = strcat(problematicFiles, filename, ", Error in trimming procedure", "\n");
            end
            progressbar(j/nfiles, m/Mic, [], []);
        end              
    end

    %plot irs to check temporal trim
%     figurename = strcat('Speaker alignment ', name);
%     figure('Name', figurename,'NumberTitle','off');
%     plot(squeeze(MIMOIR(1,:,:))');
%     title('Speaker alignment');
%     figurename = strcat('Microphone alignment ', name);
%     figure('Name', figurename,'NumberTitle','off');
%     plot(squeeze(MIMOIR(:,1,:))');
%     title('Microphone alignment');
    drawnow

    %clear RecSweep
    clear convRes
    clear convResTrim


    %% *************************************************************************************************
    %  AMBISONIC 1�order x 3�order beamformer
    % **************************************************************************************************

    disp('Ambisonic 1�x3� order beamforming...')

    % Beamforming matrix for the Zylia microphone
    [ZyliaEnc,Fs] = audioread('MIMO_Beamformer/A2B-Zylia-3E-Jul2020.wav');
    hZylia =zeros(19,16,4096); %[RMic x VMic x N]
    for m=1:1:19
        for c=1:1:16
            progressbar([], [], m/19, [])
            for s=1:1:4096
                hZylia(m,c,s)=ZyliaEnc(s+(m-1)*4096,c);
            end
        end
    end
    % figure
    % plot(squeeze(hZylia(1,1,:)));
    clear ZyliaEnc;


    % Beamforming matrix for the Lookline Dodecahedron
    [DodecEnc,Fs] = audioread('MIMO_Beamformer/Dodec-Ambix-1st-order.wav');
    hSpk =zeros(4,12,2048); %[VSpk x RSpk x N]
    for m=1:1:4
        for c=1:1:12
            for s=1:1:2048
                hSpk(m,c,s)=DodecEnc(s+(m-1)*2048,c);
            end
        end
    end
    % figure
    % plot(squeeze(hSpk(1,1,:)));
    clear DodecEnc;
    
    %Background noise Ambisonics conversion
    
    % Omni
    hZyliaW=hZylia(:,1,:);
      %  audiowrite('Recsweep.wav',RecSweep(:,1),Fs,'BitsPerSample',32);
    RecSweepW=zeros(size(RecSweep,1),1);
    for m=1:19
        RecSweepW=RecSweepW+fftfilt(squeeze(hZyliaW(m,1,:)),squeeze(RecSweep(:,m)));
        progressbar([], [], [], m/19)
        fprintf('background noise mic n.%d\n',m);
    end
    
    %Background noise time trimming with overlap and cross-fade
    silentDelta = (SilenceLength-1)*48000;
    crossFadeArea = 256;
    % Variable for storing the background noise, taken from inbetween sweeps
    BackGroundNoise = zeros(3*48000*11-10*crossFadeArea, 1);
    Win=zeros(crossFadeArea,1);             % Fade-in window
    Wcen=ones(silentDelta-2*crossFadeArea,1);   % Central window
    Wout=Win;                               % Fade-out window
    for i=1:crossFadeArea
        Win(i)=1/2*(1-cos(pi*i/crossFadeArea));
        Wout(i)=1-Win(i);
    end
    W = [Win;Wcen;Wout];                    % Complete Window
    LeftSlice = zeros(144000, 1);
    RightSlice = zeros(144000, 1);
    for i = 1:(Spk-1)
        stSample=(i-1)*(silentDelta-crossFadeArea)+1; % start sample
        enSample=stSample+silentDelta-1;              % end sample
        % fprintf('stSample=%d\n',stSample);
        try
            BackGroundNoise(stSample:enSample) = BackGroundNoise(stSample:enSample)+RecSweepW(TrimSample+DeltaSample*(i-1):TrimSample+silentDelta+DeltaSample*(i-1)-1).*W;
        catch
            % Error in stitching together the background noise, usually
            % because the recording is too short. This is not a valid
            % measurement.
            problematicFiles = strcat(problematicFiles, filename, ", Error in stitching (too short)", "\n");
        end
    end

    % Export background noise
    % audiowrite('BackgroundNoise.wav',BackGroundNoise,Fs,'BitsPerSample',32);
    store_fir(sprintf('%s_STI-Noise.wav',outname), BackGroundNoise, Fs, 0);   

    % Perform beamforming of source and microphone on the MIMO IR
    AMBI3IR = oa_matrix_convconv(hSpk,MIMOIR,hZylia);
    AMBI3IR = AMBI3IR(:,:,3071:27070);
    % Convolve the MIMOIR (room impulse response) with the Zylia matrix
    % So it is a 12x16 matrix
    STI_1W = matrix_conv(MIMOIR, hZylia);
    STI_IR = squeeze(STI_1W(1, 1, :));
    
    % Convolve the STI equalized pink noise with STI_IR, 
    % With a gain of -18.7dB
    % *10^(-18.7/20)
    STI_Signal = fftfilt(STI_IR, PinkEqFile)*10^(-3.3/20);
    
    %TODO: add normalization
    Gain=-80; % dB, to avoid clipping

    %Export 1st to 3rd order ambisonics filter matrix to WAV file
    store_fir(sprintf('%s_MIMOIR.wav',outname),MIMOIR,Fs,Gain);
    %Export 1st to 3rd order ambisonics filter matrix to WAV file
    store_fir(sprintf('%s_1AMBI_3AMBI.wav',outname),AMBI3IR,Fs,Gain);
    %Export 1st to 1st order ambisonics filter matrix to WAV file
    store_fir(sprintf('%s_1AMBI_1AMBI.wav',outname),AMBI3IR(1:4,1:4,:),Fs,Gain);
    % Export STI files
    store_fir(sprintf("%s_STI-IR.wav",outname),STI_1W(1, 1, :), Fs, Gain);
    store_fir(sprintf("%s_STI-Signal.wav", outname),STI_Signal, Fs, Gain);

    %Export W and Y mic channels with W loudspeaker channel to WAV file
    store_fir(sprintf('%s_W_WY.wav',outname),AMBI3IR(1:1,1:2,:),Fs,Gain);
    
    command = "AcouPar_pu_x64.exe " + sprintf('\"%s_W_WY.wav\"',outname);
    fprintf("%s\n", command);
    [status, results] = system(command);
end

%Close progress bar
% close(d)
% close(e)



fprintf("Done, processed %d files\n", nfiles);

disp("These files had problems!");
disp(problematicFiles); 


clear hZylia
clear hSpk
clear res
clear AMBI3IR

toc