function grid_dx = fun_grid_octree(input_grid, relative_downsample_rate)
% fun_grid_octree generates the grid information for the downsampled
% dataset. Each cube in the downsampled dataset is generated by combinding
% and downsapling the higher resolution images. 
% 
% Implemented by Xiang Ji on 04/30/2019
if nargin < 2
    relative_downsample_rate = 2;
end
if ~isfield(input_grid, 'downsample_rate')
    input_grid.downsample_rate = 1;
end
grid_dx = struct;
grid_dx.dataset_name = input_grid.dataset_name;
grid_dx.stack = input_grid.stack;
grid_dx.downsample_rate = input_grid.downsample_rate * relative_downsample_rate;
grid_dx.version = sprintf('%s_downsampled_%dx', input_grid.version, grid_dx.downsample_rate);
grid_dx.data_type = input_grid.data_type;
grid_dx.voxel_size_um = input_grid.voxel_size_um .* relative_downsample_rate;
grid_dx.grid_size = [];
grid_dx.num_grid_layer = [];
grid_dx.data_size = input_grid.data_size ./ relative_downsample_rate;
grid_dx.data_xy_size = grid_dx.data_size(1:2);
grid_dx.data_sec_num = grid_dx.data_size(3);
grid_dx.block_size = input_grid.block_size - ceil(input_grid.block_overlap * (1 - 1/relative_downsample_rate));
grid_dx.block_xy_size = grid_dx.block_size(1);
grid_dx.block_z_size = grid_dx.block_size(3);

grid_dx.block_overlap = ceil(input_grid.block_overlap ./ grid_dx.downsample_rate);

grid2D = fun_generate_grid(grid_dx.block_size(1), grid_dx.block_overlap, grid_dx.data_xy_size);
gridZ = fun_generate_grid(grid_dx.block_size(1), grid_dx.block_overlap, grid_dx.data_sec_num);
grid_dx.grid_size = [grid2D.grid_size, gridZ.grid_size];
grid_dx.num_grid_layer = gridZ.grid_size;

num_layer = grid_dx.num_grid_layer;

grid_dx.num_bbox_xy = zeros(num_layer, 1);
grid_dx.layer = 1:num_layer;
grid_dx.bbox_xy_pos_sub_in_layer = cell(num_layer, 1);
grid_dx.bbox_xy_pos_ind_in_layer = cell(num_layer, 1);
grid_dx.bbox_xy_mmll = cell(num_layer, 1);
grid_dx.bbox_xy_mmxx = cell(num_layer, 1);

grid_dx.bbox_grid_sub = cell(num_layer, 1);
grid_dx.bbox_grid_ind = cell(num_layer, 1);

grid_dx.bbox_xy_valid_mat = cell(num_layer, 1);
grid_dx.bbox_xy_label_mat = cell(num_layer, 1);


grid_dx.bbox_z_mmll = cell(num_layer, 1);
grid_dx.bbox_z_mmxx = cell(num_layer, 1);

grid_dx.bbox_xyz_mmll = cell(num_layer, 1);
grid_dx.bbox_xyz_mmxx = cell(num_layer, 1);

grid_dx.bbox_xyz_mmll_in_layer = cell(num_layer, 1);
grid_dx.bbox_xyz_mmxx_in_layer = cell(num_layer, 1);

grid_dx.bbox_volume_ratio = cell(num_layer, 1);
grid_dx.bbox_volume_ratio_array = nan(grid_dx.grid_size);

grid_dx.num_valid_cube = [];

grid_dx.bbox_child_grid_sub = cell(num_layer, 1);
grid_dx.bbox_num_child = cell(num_layer, 1);

grid_dx.grid2D = grid2D;
grid_dx.gridZ = gridZ;


[ind_offset(:,1), ind_offset(:,2), ind_offset(:,3)] = ind2sub(relative_downsample_rate* ones(1,3), 1:relative_downsample_rate^3);
ind_offset = ind_offset - relative_downsample_rate;

% Find the octree leave
for layer_idx = 1 : num_layer
    input_grid_layer_1 = (layer_idx - 1) * relative_downsample_rate + 1;
    input_grid_layer_2 = min(input_grid_layer_1 + relative_downsample_rate - 1, input_grid.num_grid_layer);
       
    tmp_bbox_volume_ratio_stack = input_grid.bbox_volume_ratio_array(:, :, input_grid_layer_1:input_grid_layer_2);
    tmp_bbox_volume_ratio_stack = padarray(tmp_bbox_volume_ratio_stack, [grid_dx.grid2D.size, 1] .* relative_downsample_rate - size(tmp_bbox_volume_ratio_stack), 'post');
    tmp_cell = mat2cell(tmp_bbox_volume_ratio_stack, ones(grid_dx.grid2D.size(1), 1).*relative_downsample_rate,...
        ones(grid_dx.grid2D.size(2), 1).*relative_downsample_rate, relative_downsample_rate);
    tmp_child_ind = cellfun(@find, tmp_cell, 'UniformOutput', false);
    tmp_child = cell(grid_dx.grid2D.size);
    tmp_num_child = cellfun(@numel, tmp_child_ind);
    
    cube_volume_ratio = fun_downsample_by_block_operation(tmp_bbox_volume_ratio_stack, @mean, relative_downsample_rate);
    
    cube_contains_sampleQ = cube_volume_ratio > 0;
    list_valid_cube_idx = find(cube_contains_sampleQ);
    num_valid_cube_in_layer = nnz(cube_contains_sampleQ);
    grid_dx.num_bbox_xy(layer_idx) = num_valid_cube_in_layer;
    
    for tmp_idx = 1 : num_valid_cube_in_layer
        bbox_idx = list_valid_cube_idx(tmp_idx);
        bbox_idx1 = grid2D.mm_idx_pos(bbox_idx,1);
        bbox_idx2 = grid2D.mm_idx_pos(bbox_idx,2);
        tmp_child{bbox_idx} = 2 .* [bbox_idx1, bbox_idx2, layer_idx] + ind_offset(tmp_child_ind{bbox_idx},:);
    end
    grid_dx.bbox_child_grid_sub{layer_idx} = tmp_child;
    grid_dx.bbox_num_child{layer_idx} = tmp_num_child;
    
    % Linear index in layer
    grid_dx.bbox_xy_pos_ind_in_layer{layer_idx} = list_valid_cube_idx;
    % Subscropt in layer
    grid_dx.bbox_xy_pos_sub_in_layer{layer_idx} = fun_ind2sub(grid_dx.grid_size(1:2), list_valid_cube_idx);
        
    % bounding box parameter in layer
    grid_dx.bbox_xy_mmll{layer_idx} = grid2D.mmll(list_valid_cube_idx, :);
    grid_dx.bbox_xy_mmxx{layer_idx} = grid2D.mmxx(list_valid_cube_idx, :);
    
    tmp_sub = cat(2, grid2D.mm_idx_pos(list_valid_cube_idx,:), layer_idx .* ones(num_valid_cube_in_layer,1));
    grid_dx.bbox_grid_sub{layer_idx} = tmp_sub;
    grid_dx.bbox_grid_ind{layer_idx} = sub2ind(grid_dx.grid_size, tmp_sub(:, 1), tmp_sub(:, 2), tmp_sub(:, 3));
    
    % 2D information in grid matrix form
    grid_dx.bbox_xy_valid_mat{layer_idx} = cube_contains_sampleQ;
    grid_dx.bbox_xy_label_mat{layer_idx} = zeros(size(cube_contains_sampleQ));
    grid_dx.bbox_xy_label_mat{layer_idx}(cube_contains_sampleQ) = 1 : num_valid_cube_in_layer;
   
    grid_dx.bbox_volume_ratio{layer_idx} = cube_volume_ratio;
    grid_dx.bbox_volume_ratio_array(:, :, layer_idx) = cube_volume_ratio;

    grid_dx.bbox_z_mmll{layer_idx} = gridZ.mmll(layer_idx, :);
    grid_dx.bbox_z_mmxx{layer_idx} = gridZ.mmxx(layer_idx, :);
    
    grid_dx.bbox_xyz_mmll{layer_idx} = cat(2,grid_dx.bbox_xy_mmll{layer_idx}(:,1:2),ones(grid_dx.num_bbox_xy(layer_idx),1)*gridZ.ul(layer_idx),...
        grid_dx.bbox_xy_mmll{layer_idx}(:,3:4),ones(grid_dx.num_bbox_xy(layer_idx) ,1)*gridZ.mmll(layer_idx,2) );
    
    grid_dx.bbox_xyz_mmxx{layer_idx} = cat(2,grid_dx.bbox_xy_mmll{layer_idx}(:,1:2),ones(grid_dx.num_bbox_xy(layer_idx),1)*gridZ.ul(layer_idx),...
        grid_dx.bbox_xy_mmxx{layer_idx}(:,3:4),ones(grid_dx.num_bbox_xy(layer_idx) ,1)*gridZ.mmxx(layer_idx,2) );
    
    grid_dx.bbox_xyz_mmll_in_layer{layer_idx} = cat(2,grid_dx.bbox_xy_mmll{layer_idx}(:,1:2),ones(grid_dx.num_bbox_xy(layer_idx),1),...
        grid_dx.bbox_xy_mmll{layer_idx}(:,3:4),ones(grid_dx.num_bbox_xy(layer_idx) ,1)*gridZ.ll(layer_idx) );
    
    grid_dx.bbox_xyz_mmxx_in_layer{layer_idx} = cat(2,grid_dx.bbox_xy_mmxx{layer_idx}(:,1:2),ones(grid_dx.num_bbox_xy(layer_idx),1),...
        grid_dx.bbox_xy_mmxx{layer_idx}(:,3:4), ones(grid_dx.num_bbox_xy(layer_idx) ,1)*gridZ.ll(layer_idx) );
end
grid_dx.num_valid_cube = sum(grid_dx.num_bbox_xy);
grid_dx.bbox_grid_ind_list = cat(1, grid_dx.bbox_grid_ind{:});
grid_dx.bbox_grid_sub_list = cat(1, grid_dx.bbox_grid_sub{:});
grid_dx.bbox_grid_label_array = nan(grid_dx.grid_size);
grid_dx.bbox_grid_label_array(grid_dx.bbox_grid_ind_list) = 1 : grid_dx.num_valid_cube;
grid_dx.bbox_xyz_mmll_list = cat(1, grid_dx.bbox_xyz_mmll{:});
grid_dx.bbox_xyz_mmxx_list = cat(1, grid_dx.bbox_xyz_mmxx{:});

DataManager = FileManager;
DataManager.write_grid_info(grid_dx, grid_dx.dataset_name, grid_dx.stack, grid_dx.version);
end