%% Set Parameters
training = true;
rootdir = '/Users/blair/Desktop/bee/AnnotatedTags/tags9621/good/';
% rootdir = '/Users/blair/Desktop/bee/tags/MVI9621/';
ext = '.tif';
lang = '/Users/blair/dev/beetag/matlab/training/dgt/dgt/tessdata/dgt.traineddata';

%% Get Input Paths
files = dir(fullfile(rootdir, ['*' ext]));
dirIdx = [files.isdir];
files = {files(~dirIdx).name}';
numImg = length(files);

%build full file path
for i = 1:numImg
    files{i} = fullfile(rootdir,files{i});
end

%load templates
load dgt_templates.mat;

%% Process Images
passed = 0;

for i = 1:numImg
    %read image
    img = imread(files{i});
    [~, name, ~] = fileparts(files{i});
    
    %get ground truth digits if in training mode
    if training
        digits = name(1:3);
    end
    
    %preprocess
    img = imcomplement(rgb2gray(img));
%     img = tagpreproc(img);
%     imwrite(img, fullfile('/Users/blair/Desktop/bee/tags/TrainingFramesSelected_grayclean/',[name '.tif']));
    
    %process tag and rotated tag
    rot = [-4, -2, -1, -0.5, 0, 0.5, 1, 2, 4, 176, 178, 179, 179.5 180];
    results = cell(1,length(rot));
    
    for j = 1:length(rot)
        %rotate image
        rotimg = imrotate(img,rot(j));
        
        for k = 1:length(templates)
            %get template dimensions for bbox
            template = imresize(templates{k},0.35);
            [h,w] = size(template);
            
            %normalized cross correlation
            nxc = normxcorr2(template, rotimg);

            %find maxima
            hLocalMax = vision.LocalMaximaFinder;
            hLocalMax.MaximumNumLocalMaxima = 3;
            hLocalMax.NeighborhoodSize = [h w];
            hLocalMax.Threshold = 0;

            maxima = step(hLocalMax, nxc);
            
            %get confidence levels
            conf = nxc(maxima);
            results{j}.DigitConfidences = padarray(conf, 3-length(conf),'post');
            
            %compute average confidence
            results{j}.AverageConfidence = mean(results{j}.DigitConfidences);
            
            %define bounding boxes
            results{j}.BoundingBox = zeros(size(maxima,1),4);
            results{j}.BoundingBox(:,1) = maxima(:,1) - floor(w/2);
            results{j}.BoundingBox(:,2) = maxima(:,2) - floor(h/2);
            results{j}.BoundingBox(:,3) = w;
            results{j}.BoundingBox(:,4) = h;
            
            %keep at most 3 digits by confidence level
            conf = results{j}.ocr.CharacterConfidences;
            conf(isnan(conf)) = 0;      %convert NaN to 0 for correct sorting

            if length(conf) > 2            
                %sort digits by confidence level
                [~,idx] = sort(conf, 'descend');
                idx = sort(idx(1:3), 'ascend');
                results{j}.DigitConfidences = conf(idx);

                %compute average confidence
                results{j}.AverageConfidence = mean(conf(idx));

                %get and clean digits with highest confidence
                text = results{j}.ocr.Text(idx);
                text = strtrim(text);
                text(text == ' ') = ''; 
            else
                %add digit confidence
                results{j}.DigitConfidences = conf;

                %compute average confidence
                results{j}.AverageConfidence = mean(conf);

                %clean digits
                text = strtrim(results{j}.ocr.Text);
                text(text == ' ') = ''; 
            end %if

            %add extracted digits
            results{j}.Digits = text; 

        end %for
    end %for

    %determine best orientation
    [~,orIdx] = max(results{:}.AverageConfidence);
    text = results{orIdx}.Digits;

    %print results
    if training
        fprintf('Actual: %3s | OCR: %3s | Conf: (%f, %f, %f)\n', digits, text, dgtConf)
        if strcmp(digits,text)
            passed = passed + 1;
        end
    else
        fprintf('File %s: %s\n', name, text)
    end
end

if training
    fprintf('Accuracy = %.3f\n', passed/numImg*100);
end