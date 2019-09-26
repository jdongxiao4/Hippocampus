uf = unityfile('auto');
el = eyelink('auto');
rp = rplparallel('auto');

true_timestamps = rp.data.timeStamps';
true_timestamps = true_timestamps(:) * 1000; % in ms

el_trial_timestamps_flat = el.data.trial_timestamps';
el_trial_timestamps_flat = el_trial_timestamps_flat(:);

uf_unityTriggers_flat = uf.data.unityTriggers';
uf_unityTriggers_flat = uf_unityTriggers_flat(:);

% when unityTriggers looks for [2 5], diff the [3 6] indices from unityTime
% for duration between cue off and end trial.

dubious_counter = 0;
dubious_collector = [];

for i = 1:length(true_timestamps)-1
    
    true_start = true_timestamps(i);
    true_end = true_timestamps(i+1);
    true_diff = true_end - true_start;
    
    current_start = el_trial_timestamps_flat(i);
    current_end = el_trial_timestamps_flat(i+1);
    current_chunk = double(el.data.timestamps(current_start:current_end));
    current_diff = double(current_chunk(length(current_chunk)) - current_chunk(1));
    current_start_time = current_chunk(1);
    current_end_time = current_chunk(length(current_chunk));
    
    current_chunk = (current_chunk - current_start_time)* true_diff/current_diff; % now scaled to rpl timing  
    current_chunk = current_chunk + current_start_time; % shifted back to original start
    shifting_needed = current_chunk(length(current_chunk)) - current_end_time; % finds how much every subsequent timepoints need to shift by to fix gap for next two points
    
    el.data.timestamps(current_start:current_end) = uint32(current_chunk);
    el.data.timestamps(current_end+1:length(el.data.timestamps)) = el.data.timestamps(current_end+1:length(el.data.timestamps)) + shifting_needed; % every subsequent timepoints shifted to compensate for earlier compression/expansion
    
    disp(['iteration ' num2str(i)]);
    disp('timestamps for eyelink were shifted back by (ms):');
    disp(shifting_needed);
      
    %%%%%%%%%%%%%%%%%%% unity shifting starts here %%%%%%%%%%%%%%%%%%%%%
    
    true_diff = true_diff/1000; % diff from rpl in seconds, for comparison with unityfile timings
    
    current_start = uf_unityTriggers_flat(i)+1;
    current_end = uf_unityTriggers_flat(i+1)+1;
    current_chunk = uf.data.unityTime(current_start:current_end);
    current_diff = current_chunk(length(current_chunk)) - current_chunk(1);
    current_start_time = current_chunk(1);
    current_end_time = current_chunk(length(current_chunk));
    
    dubious = 0;
    if abs(current_diff - true_diff) > 2
        dubious = 1;
    end
    
    current_chunk = (current_chunk - current_start_time)* true_diff/current_diff; % now scaled to rpl timing  
    current_chunk = current_chunk + current_start_time; % shifted back to original start
    shifting_needed = current_chunk(length(current_chunk)) - current_end_time; % finds how much every subsequent timepoints need to shift by to fix gap for next two points

    uf.data.unityTime(current_start:current_end) = current_chunk;
    uf.data.unityTime(current_end+1:length(uf.data.unityTime)) = uf.data.unityTime(current_end+1:length(uf.data.unityTime)) + shifting_needed; % every subsequent timepoints shifted to compensate for earlier compression/expansion
    
    disp('timestamps for unityfile were shifted back by (s):');
    disp(shifting_needed);
    if dubious == 1
        
        chunk_size = length(uf.data.unityTime(current_start:current_end));
        uf.data.unityTime(current_start:current_end-1) = repmat(uf.data.unityTime(current_start),1,chunk_size-1); % because the trial duration in uf differs too much from that of rpl, we mark this trial as unusable by setting all but the last value to the initial value (last value not changed, so that next trial can be evaluated).
        
        dubious_counter = dubious_counter + 1;
        dubious_collector = [dubious_collector i];
        disp('but disparity between rpl and unity was quite large >2 ms duration');
        disp(abs(current_diff - true_diff));
        
    end
    
end

disp('dubious counter:');
disp(dubious_counter);
disp('dubious location(s):');
disp(dubious_collector);


%%%%% shifting all to reference 0 as ripple start time %%%%%

if rp.data.Args.Data.markers(1) == 84
    true_session_start = rp.data.Args.Data.timeStamps(1);
    rp.data.session_start_sec = true_session_start;
    session_trial_duration = rp.data.timeStamps(1,1) - true_session_start;
    session_trial_duration = session_trial_duration * 1000; % true delay between unity start and first trial is now in milliseconds
    
    finding_index = find(el.data.timestamps==el.data.session_start);
    finding_index = finding_index(1);
        
    el_session_trial_chunk = double(el.data.timestamps(finding_index:el.data.trial_timestamps(1,1)));
    last_point = el_session_trial_chunk(end);
    first_point = el_session_trial_chunk(1);
    scaled_chunk = ((el_session_trial_chunk-el_session_trial_chunk(1))/double(last_point-first_point))*session_trial_duration;
    scaled_chunk = scaled_chunk + first_point;
    shifting_needed = scaled_chunk(end) - last_point;
    
    el.data.timestamps(el.data.trial_timestamps(1,1)+1:end) = el.data.timestamps(el.data.trial_timestamps(1,1)+1:end) + shifting_needed;
    el.data.timestamps(finding_index:el.data.trial_timestamps(1,1)) = scaled_chunk;
    
    target = true_session_start * 1000;
    full_shift = el.data.session_start - target;
    el.data.timestamps = uint32(el.data.timestamps - full_shift);
    el.data.session_start_index = finding_index;
    
    session_trial_duration = rp.data.timeStamps(1,1) - true_session_start;
    uf_session_trial_chunk = uf.data.unityTime(1:uf.data.unityTriggers(1,1));
    last_point = uf_session_trial_chunk(end);
    scaled_chunk = (uf_session_trial_chunk/last_point) * session_trial_duration;
    shifting_needed = scaled_chunk(end) - last_point;
    
    uf.data.unityTime(uf.data.unityTriggers(1,1)+1:end) = uf.data.unityTime(uf.data.unityTriggers(1,1)+1:end) + shifting_needed;
    uf.data.unityTime(1:uf.data.unityTriggers(1,1)) = scaled_chunk;

    uf.data.unityTime = uf.data.unityTime + true_session_start;
    
else
    disp('session start marker not recognised');
    disp('unable to align timings accurately for now');
end
    
%%%%%%%%%%%%%%%%%%%% updating unityData and unityTrialTime %%%%%%%%%%%%%%%

new_deltas = diff(uf.data.unityTime);
uf.data.unityData(:,2) = new_deltas;

for col = 1:size(uf.data.unityTrialTime, 2)
    
    duration = uf.data.unityTime(uf.data.unityTriggers(col,3)+1) - uf.data.unityTime(uf.data.unityTriggers(col,2)+1);
    neg_count = sum(isnan(uf.data.unityTrialTime(:,col)));
    valued_length = size(uf.data.unityTrialTime, 1) - neg_count;
    arr = uf.data.unityTrialTime(1:valued_length,col);
    arr_max = arr(end);
    arr = arr*duration/arr_max;
    
    uf.data.unityTrialTime(1:length(arr),col) = arr;
    
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


save('unityfile2.mat', 'uf');
save('eyelink2.mat', 'el');
save('rplparallel2.mat', 'rp');

% out = uf.data;
% out2 = el.data;
% out3 = rp.data;







