/*
 * Software License Agreement (BSD License)
 *
 *  Copyright (c) 2016 Case Western Reserve University
 *
 *    Ran Hao <rxh349@case.edu>
 *
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions
 *  are met:
 *
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above
 *     copyright notice, this list of conditions and the following
 *     disclaimer in the documentation and/or other materials provided
 *     with the distribution.
 *   * Neither the name of Case Western Reserve University, nor the names of its
 *     contributors may be used to endorse or promote products derived
 *     from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 *  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 *  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 *  FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 *  COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 *  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 *  BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 *  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 *  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 *  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 *  ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 *  POSSIBILITY OF SUCH DAMAGE.
 *
 */

#include <ros/ros.h>
#include <boost/random.hpp>
#include "tool_model_gpu/tool_model.h"


using cv_projective::reprojectPoint;
using cv_projective::transformPoints;
using namespace std;

boost::mt19937 rng((const uint32_t &) time(0));

ToolModel::ToolModel() {

    ///adjust the model params according to the tool geometry
    offset_body = 0.4560; //0.4560
    offset_ellipse = offset_body;
    offset_gripper = offset_ellipse+ 0.007;

//    offset_body = 0.4570; //0.4560
//    offset_ellipse = offset_body;
//    offset_gripper = offset_ellipse+ 0.009;

    /****initialize the vertices fo different part of tools****/
    tool_model_pkg = ros::package::getPath("tool_model");

    std::string cylinder = tool_model_pkg + "/tool_parts/cyliner_tense_end_face.obj"; //"/tense_cylinde_2.obj", test_cylinder_3, cyliner_tense_end_face, refine_cylinder_3
    std::string ellipse = tool_model_pkg + "/tool_parts/refine_ellipse_3.obj";
    std::string gripper1 = tool_model_pkg + "/tool_parts/gripper2_1.obj";
    std::string gripper2 = tool_model_pkg + "/tool_parts/gripper2_2.obj";


    load_model_vertices(cylinder.c_str(),
                        body_vertices, body_Vnormal, body_faces, body_neighbors);
//    load_model_vertices(ellipse.c_str(),
//                        ellipse_vertices, ellipse_Vnormal, ellipse_faces, ellipse_neighbors);
//    load_model_vertices(gripper1.c_str(), griper1_vertices,
//                        griper1_Vnormal, griper1_faces, griper1_neighbors);
//    load_model_vertices(gripper2.c_str(), griper2_vertices,
//                        griper2_Vnormal, griper2_faces, griper2_neighbors);


    modify_model_(body_vertices, body_Vnormal, body_Vpts, body_Npts, offset_body, body_Vmat, body_Nmat);
//    modify_model_(ellipse_vertices, ellipse_Vnormal, ellipse_Vpts, ellipse_Npts, offset_ellipse, ellipse_Vmat,
//                  ellipse_Nmat);
//    modify_model_(griper1_vertices, griper1_Vnormal, griper1_Vpts, griper1_Npts, offset_gripper, gripper1_Vmat,
//                  gripper1_Nmat);
//    modify_model_(griper2_vertices, griper2_Vnormal, griper2_Vpts, griper2_Npts, offset_gripper, gripper2_Vmat,
//                  gripper2_Nmat);


    getFaceInfo(body_faces, body_Vpts, body_Npts, bodyFace_normal, bodyFace_centroid);
//    getFaceInfo(ellipse_faces, ellipse_Vpts, ellipse_Npts, ellipseFace_normal, ellipseFace_centroid);
//    getFaceInfo(griper1_faces, griper1_Vpts, griper1_Npts, gripper1Face_normal, gripper1Face_centroid);
//    getFaceInfo(griper2_faces, griper2_Vpts, griper2_Npts, gripper2Face_normal, gripper2Face_centroid);

    srand((unsigned) time(NULL)); //for the random number generator, use only once

};

double ToolModel::randomNumber(double stdev, double mean) {

    boost::normal_distribution<> nd(mean, stdev);
    boost::variate_generator<boost::mt19937 &, boost::normal_distribution<> > var_nor(rng, nd);
    double d = var_nor();

    return d;

};

double ToolModel::randomNum(double min, double max){

    /// srand((unsigned) time( NULL));  //do this in main or constructor
    int N = 999;

    double randN = rand() % (N + 1) / (double) (N + 1);  // a rand number frm 0 to 1
    double res = randN * (max - min) + min;

    return res;
};

void ToolModel::ConvertInchtoMeters(std::vector<cv::Point3d> &input_vertices) {

    int size = (int) input_vertices.size();
    for (int i = 0; i < size; ++i) {
        input_vertices[i].x = input_vertices[i].x * 0.0254;
        input_vertices[i].y = input_vertices[i].y * 0.0254;
        input_vertices[i].z = input_vertices[i].z * 0.0254;
    }
};

void ToolModel::load_model_vertices(const char *path, std::vector<glm::vec3> &out_vertices,
                                    std::vector<glm::vec3> &vertex_normal,
                                    std::vector<int> &out_faces,
                                    std::vector<int> &neighbor_faces) {

    std::vector<unsigned int> vertexIndices, uvIndices, normalIndices;
    std::vector<glm::vec2> temp_uvs;

    std::vector<int> temp_face;
    temp_face.resize(6);  //need three vertex and corresponding normals

    FILE *file = fopen(path, "r");
    if (file == NULL) {
        printf("Impossible to open the file ! Are you in the right path ?\n");
        return;
    }
    while (1) {

        char lineHeader[128];
        // read the first word of the line
        int res = fscanf(file, "%s", lineHeader);
        if (res == EOF)
            break; // EOF = End Of File. Quit the loop.

        // else : parse lineHeader
        if (strcmp(lineHeader, "v") == 0) {
            glm::vec3 vertex;

            fscanf(file, "%f %f %f\n", &vertex.x, &vertex.y, &vertex.z);
            //temp_vertices.push_back(vertex);
            out_vertices.push_back(vertex);
        } else if (strcmp(lineHeader, "vt") == 0) {
            glm::vec2 uv;
            fscanf(file, "%f %f\n", &uv.x, &uv.y);
            // cout<<"uv"<<uv.x<<endl;
            temp_uvs.push_back(uv);
        } else if (strcmp(lineHeader, "vn") == 0) {
            glm::vec3 normal;
            fscanf(file, "%f %f %f\n", &normal.x, &normal.y, &normal.z);
            //temp_normals.push_back(normal);
            vertex_normal.push_back(normal);

        } else if (strcmp(lineHeader, "f") == 0) {

            unsigned int vertexIndex[3], uvIndex[3], normalIndex[3];
            int matches = fscanf(file, "%d/%d/%d %d/%d/%d %d/%d/%d\n", &vertexIndex[0], &uvIndex[0], &normalIndex[0],
                                 &vertexIndex[1], &uvIndex[1], &normalIndex[1], &vertexIndex[2], &uvIndex[2],
                                 &normalIndex[2]);
            if (matches != 9) {
                ROS_ERROR("File can't be read by our simple parser : ( Try exporting with other options\n");
            }

            /* this mean for later use, just in case */
            vertexIndices.push_back(vertexIndex[0]);
            vertexIndices.push_back(vertexIndex[1]);
            vertexIndices.push_back(vertexIndex[2]);
            uvIndices.push_back(uvIndex[0]);
            uvIndices.push_back(uvIndex[1]);
            uvIndices.push_back(uvIndex[2]);
            normalIndices.push_back(normalIndex[0]);
            normalIndices.push_back(normalIndex[1]);
            normalIndices.push_back(normalIndex[2]);

            /////////////UPDATED 07.24///////////////
            out_faces.push_back( vertexIndex[0] - 1);
            out_faces.push_back( vertexIndex[1] - 1);
            out_faces.push_back( vertexIndex[2] - 1);
            out_faces.push_back( normalIndex[0] - 1);
            out_faces.push_back( normalIndex[1] - 1);
            out_faces.push_back( normalIndex[2] - 1);
        }
    }

    int face_size = out_faces.size()/6;

    std::vector<int> temp_vec;
    std::vector<std::vector<int> > neighbor_collection;
    neighbor_collection.resize(face_size);

    for (int i = 0; i < face_size; ++i) {

        for (int j = 0; j < face_size; ++j) {
            if (j != i) {  //no repeats
                std::vector<int> v1(out_faces.begin() +6 *i, out_faces.begin() + 6*i + 6);
                std::vector<int> v2(out_faces.begin() +6 *j, out_faces.begin() + 6*j + 6);

                int match = Compare_vertex(v1, v2, temp_vec);

                if (match == 2) //so face i and face j share an edge
                {
                    //////////UPDATED 07.24////////////////////
                    neighbor_collection[i].push_back(j); // mark the neighbor face index
                    neighbor_collection[i].push_back(temp_vec[0]);  //first vertex
                    neighbor_collection[i].push_back(temp_vec[1]);  //corresponding normal
                    neighbor_collection[i].push_back(temp_vec[2]);  //second vertex
                    neighbor_collection[i].push_back(temp_vec[3]);  //corresponding normal
                }
                temp_vec.clear();
            }

        }

        int neighbor_size = neighbor_collection[i].size();
        if(neighbor_size < 15){
            for (int i = neighbor_size; i < 15; ++i) {
                neighbor_collection[i].push_back(-1);
            }
        }
    }

//    ROS_INFO_STREAM("neighbor_faces SIZE " << neighbor_collection.size());
//    ROS_INFO_STREAM("size of each : "<<neighbor_collection[5].size());

    for (int k = 0; k < face_size; ++k) {
        for (int i = 0; i < 15; ++i) {
            neighbor_faces.push_back(neighbor_collection[k][i]);
        }

    }
//
//    for (int k = 0; k < 10 * 15; ++k) {
//        ROS_INFO_STREAM("neighbor_faces SIZE " << neighbor_faces[k]);
//    }

    printf("loaded file %s successfully.\n", path);
};

void ToolModel::Convert_glTocv_pts(std::vector<glm::vec3> &input_vertices, std::vector<cv::Point3d> &out_vertices) {

    unsigned long vsize = input_vertices.size();

    out_vertices.resize(vsize);
    for (int i = 0; i < vsize; ++i) {
        out_vertices[i].x = input_vertices[i].x;
        out_vertices[i].y = input_vertices[i].y;
        out_vertices[i].z = input_vertices[i].z;
    }
};

cv::Mat ToolModel::camTransformMats(cv::Mat &cam_mat, cv::Mat &input_mat) {
    /*cam mat should be a 4x4 extrinsic parameter*/
    cv::Mat output_mat = cam_mat * input_mat; //transform the obj to camera frames, g_CT

    return output_mat;
};

//////////UPDATED 07.24////////////////////
void ToolModel::getFaceInfo(const std::vector<int> &input_faces,
                            const std::vector<cv::Point3d> &input_vertices,
                            const std::vector<cv::Point3d> &input_Vnormal, cv::Mat &face_normals,
                            cv::Mat &face_centroids) {

    int face_size = input_faces.size()/6;
    face_normals = cv::Mat(4, face_size, CV_64FC1);
    face_centroids = cv::Mat(4, face_size, CV_64FC1);

    for (int i = 0; i < face_size; ++i) {
        int v1 = input_faces[6*i];
        int v2 = input_faces[6*i+1];
        int v3 = input_faces[6*i+2];
        int n1 = input_faces[6*i+3];
        int n2 = input_faces[6*i+4];
        int n3 = input_faces[6*i+5];

        cv::Point3d pt1 = input_vertices[v1];
        cv::Point3d pt2 = input_vertices[v2];
        cv::Point3d pt3 = input_vertices[v3];

        cv::Point3d normal1 = input_Vnormal[n1];
        cv::Point3d normal2 = input_Vnormal[n2];
        cv::Point3d normal3 = input_Vnormal[n3];

        cv::Point3d fnormal = FindFaceNormal(pt1, pt2, pt3, normal1, normal2,
                                             normal3); //knowing the direction and normalized

        face_normals.at<double>(0, i) = fnormal.x;
        face_normals.at<double>(1, i) = fnormal.y;
        face_normals.at<double>(2, i) = fnormal.z;
        face_normals.at<double>(3, i) = 0;

        cv::Point3d face_point = pt1 + pt2 + pt3;

        face_point.x = face_point.x / 3.000000;
        face_point.y = face_point.y / 3.000000;
        face_point.z = face_point.z / 3.000000;
        face_point = Normalize(face_point);

        face_centroids.at<double>(0, i) = face_point.x;
        face_centroids.at<double>(1, i) = face_point.y;
        face_centroids.at<double>(2, i) = face_point.z;
        face_centroids.at<double>(3, i) = 1;

    }

};

cv::Point3d ToolModel::crossProduct(cv::Point3d &vec1, cv::Point3d &vec2) {    //3d vector

    cv::Point3d res_vec;
    res_vec.x = vec1.y * vec2.z - vec1.z * vec2.y;
    res_vec.y = vec1.z * vec2.x - vec1.x * vec2.z;
    res_vec.z = vec1.x * vec2.y - vec1.y * vec2.x;

    return res_vec;
};

double ToolModel::dotProduct(cv::Point3d &vec1, cv::Point3d &vec2) {
    double dot_res;
    dot_res = vec1.x * vec2.x + vec1.y * vec2.y + vec1.z * vec2.z;

    return dot_res;
};

cv::Point3d ToolModel::Normalize(cv::Point3d &vec1) {
    cv::Point3d norm_res;

    double norm = vec1.x * vec1.x + vec1.y * vec1.y + vec1.z * vec1.z;

    norm = pow(norm, 0.5);

    norm_res.x = vec1.x / norm;
    norm_res.y = vec1.y / norm;
    norm_res.z = vec1.z / norm;

    return norm_res;

};

cv::Point3d ToolModel::FindFaceNormal(cv::Point3d &input_v1, cv::Point3d &input_v2, cv::Point3d &input_v3,
                                      cv::Point3d &input_n1, cv::Point3d &input_n2, cv::Point3d &input_n3) {
    cv::Point3d temp_v1;
    cv::Point3d temp_v2;

    temp_v1.x = input_v1.x - input_v2.x;    //let temp v1 be v1-v2
    temp_v1.y = input_v1.y - input_v2.y;
    temp_v1.z = input_v1.z - input_v2.z;

    temp_v2.x = input_v1.x - input_v3.x;    //let temp v1 be v1-v3
    temp_v2.y = input_v1.y - input_v3.y;
    temp_v2.z = input_v1.z - input_v3.z;

    cv::Point3d res = crossProduct(temp_v1, temp_v2);

    double outward_normal_1 = dotProduct(res, input_n1);
    double outward_normal_2 = dotProduct(res, input_n2);
    double outward_normal_3 = dotProduct(res, input_n3);
    if ((outward_normal_1 < 0) || (outward_normal_2 < 0) || (outward_normal_3 < 0)) {
        res = -res;
    }

    return res;  // knowing the direction

};


int ToolModel::Compare_vertex(std::vector<int> &vec1, std::vector<int> &vec2, std::vector<int> &match_vec) {
    int match_count = 0;
    if (vec1.size() != vec2.size())  ///face vectors
    {
        printf("Two vectors are not in the same size \n");
    } else {
        for (int j = 0; j < 3; ++j) {
            if (vec1[0] == vec2[j]) {
                match_count += 1;
                match_vec.push_back(vec1[0]);   //vertex
                match_vec.push_back(vec1[3]);  // corresponding vertex normal

            }

        }

        for (int j = 0; j < 3; ++j) {
            if (vec1[1] == vec2[j]) {
                match_count += 1;
                match_vec.push_back(vec1[1]);
                match_vec.push_back(vec1[4]);  // corresponding vertex normal

            }

        }

        for (int j = 0; j < 3; ++j) {
            if (vec1[2] == vec2[j]) {
                match_count += 1;
                match_vec.push_back(vec1[2]);
                match_vec.push_back(vec1[5]);  // corresponding vertex normal

            }

        }
    }

    return match_count;
};

/*******This function is to do transformations to the raw data from the loader, to offset each part*******/
void ToolModel::modify_model_(std::vector<glm::vec3> &input_vertices, std::vector<glm::vec3> &input_Vnormal,
                              std::vector<cv::Point3d> &input_Vpts, std::vector<cv::Point3d> &input_Npts,
                              double &offset, cv::Mat &input_Vmat, cv::Mat &input_Nmat) {

    Convert_glTocv_pts(input_vertices, input_Vpts);
    ConvertInchtoMeters(input_Vpts);

    int size = input_Vpts.size();
    for (int i = 0; i < size; ++i) {
        input_Vpts[i].y = input_Vpts[i].y - offset;
    }
    Convert_glTocv_pts(input_Vnormal, input_Npts); //not using homogeneous for v weight now
    ConvertInchtoMeters(input_Npts);

    input_Vmat = cv::Mat(4, size, CV_64FC1);

    for (int i = 0; i < size; ++i) {
        input_Vmat.at<double>(0, i) = input_Vpts[i].x;
        input_Vmat.at<double>(1, i) = input_Vpts[i].y;
        input_Vmat.at<double>(2, i) = input_Vpts[i].z;
        input_Vmat.at<double>(3, i) = 1;
    }

    int Nsize = input_Npts.size();
    input_Nmat = cv::Mat(4, Nsize, CV_64FC1);

    for (int i = 0; i < Nsize; ++i) {
        input_Nmat.at<double>(0, i) = input_Npts[i].x;
        input_Nmat.at<double>(1, i) = input_Npts[i].y;
        input_Nmat.at<double>(2, i) = input_Npts[i].z;
        input_Nmat.at<double>(3, i) = 0;
    }

};

ToolModel::toolModel ToolModel::setRandomConfig(const toolModel &seeds, const double &theta_cylinder, const double &theta_oval, const double &theta_open, double &step){

    toolModel newTool = seeds;  //BODY part is done here

    double dev = randomNumber(step, 0);

    newTool.tvec_cyl(0) = seeds.tvec_cyl(0) + dev;

    dev = randomNumber(step, 0);
    newTool.tvec_cyl(1) = seeds.tvec_cyl(1) + dev;

    dev = randomNumber(step, 0);
    newTool.tvec_cyl(2) = seeds.tvec_cyl(2)+ dev;

    dev = randomNumber(step, 0);
    newTool.rvec_cyl(0) = seeds.rvec_cyl(0)+ dev;

    dev = randomNumber(step, 0);
    newTool.rvec_cyl(1) = seeds.rvec_cyl(1)+ dev;

    dev = randomNumber(step, 0);
    newTool.rvec_cyl(2) = seeds.rvec_cyl(2)+ dev;

    /************** sample the angles of the joints **************/
    //set positive as clockwise
    double theta_1 = theta_cylinder + randomNumber(0.0001, 0);   // tool rotation
    double theta_grip_1 = theta_oval + randomNumber(0.0001, 0); // oval rotation
    double theta_grip_2 = theta_open + randomNumber(0.0001, 0);

    computeEllipsePose(newTool, theta_1, theta_grip_1, theta_grip_2);

    return newTool;
};

ToolModel::toolModel ToolModel::gaussianSampling(const toolModel &max_pose, double &step){

    toolModel gaussianTool;  //new sample

    double dev_pos = randomNumber(step, 0);
    gaussianTool.tvec_cyl(0) = max_pose.tvec_cyl(0)+ dev_pos;

    dev_pos = randomNumber(step, 0);
    gaussianTool.tvec_cyl(1) = max_pose.tvec_cyl(1)+ dev_pos;

    dev_pos = randomNumber(step, 0);
    gaussianTool.tvec_cyl(2) = max_pose.tvec_cyl(2)+ dev_pos;

    double dev_ori = randomNumber(step, 0);
    gaussianTool.rvec_cyl(0) = max_pose.rvec_cyl(0)+ dev_ori;

    dev_ori = randomNumber(step, 0);
    gaussianTool.rvec_cyl(1) = max_pose.rvec_cyl(1)+ dev_ori;

    dev_ori = randomNumber(step, 0);
    gaussianTool.rvec_cyl(2) = max_pose.rvec_cyl(2)+ dev_ori;

    /************** sample the angles of the joints **************/
    //set positive as clockwise
    double theta_ = randomNumber(0.001, 0);    //-90,90
    double theta_grip_1 = randomNumber(0.001, 0);
    double theta_grip_2 = randomNumber(0.001, 0);

    computeRandomPose(max_pose, gaussianTool, theta_, theta_grip_1, theta_grip_2);

    return gaussianTool;

};

/*using ellipse pose to compute cylinder pose, this is for particle filter*/
void ToolModel::computeRandomPose(const toolModel &seed_pose, toolModel &inputModel, const double &theta_tool, const double &theta_grip_1,
                                  const double &theta_grip_2) {

    cv::Mat I = cv::Mat::eye(3, 3, CV_64FC1);
    ///take cylinder part as the origin
    cv::Mat q_temp(4, 1, CV_64FC1);

    cv::Mat q_ellipse_ = cv::Mat(4, 1, CV_64FC1);
    q_ellipse_.at<double>(0, 0) = 0;
    q_ellipse_.at<double>(1, 0) = 0.02; //notice this mean y is pointing to the gripper tip, should be the same with computeEllipsePose
    q_ellipse_.at<double>(2, 0) = 0;
    q_ellipse_.at<double>(3, 0) = 1;

    q_temp = transformPoints(q_ellipse_, cv::Mat(inputModel.rvec_cyl),
                             cv::Mat(inputModel.tvec_cyl)); //transform the ellipse coord according to cylinder pose

    inputModel.tvec_elp(0) = q_temp.at<double>(0, 0);
    inputModel.tvec_elp(1) = q_temp.at<double>(1, 0);
    inputModel.tvec_elp(2) = q_temp.at<double>(2, 0);

    /*********** computations for oval kinematics **********/
    /********oval part using the best particle pose ********/
    cv::Mat rot_ellipse(3,3,CV_64FC1);
    cv::Rodrigues(seed_pose.rvec_elp, rot_ellipse);

    double cos_theta = cos(theta_tool);
    double sin_theta = sin(theta_tool);

    cv::Mat g_ellipse = (cv::Mat_<double>(3,3) << cos_theta, -sin_theta, 0,
            sin_theta, cos_theta, 0,
            0,0, 1);

    cv::Mat rot_new = g_ellipse * rot_ellipse;
    cv::Mat temp_vec(3,1,CV_64FC1);
    cv::Rodrigues(rot_new, inputModel.rvec_elp);

    /*********** computations for gripper kinematics **********/
    cv::Mat test_gripper(3, 1, CV_64FC1);
    test_gripper.at<double>(0, 0) = 0;
    test_gripper.at<double>(1, 0) = offset_gripper - offset_ellipse;
    test_gripper.at<double>(2, 0) = 0;

    cv::Mat rot_elp(3, 3, CV_64FC1);
    cv::Rodrigues(inputModel.rvec_elp, rot_elp);  // get rotation mat of the ellipse

    cv::Mat q_rot(3, 1, CV_64FC1);
    q_rot = rot_elp * test_gripper;

    inputModel.tvec_grip1(0) = q_rot.at<double>(0, 0) + inputModel.tvec_elp(0);
    inputModel.tvec_grip1(1) = q_rot.at<double>(1, 0) + inputModel.tvec_elp(1);
    inputModel.tvec_grip1(2) = q_rot.at<double>(2, 0) + inputModel.tvec_elp(2);

    inputModel.tvec_grip2(0) = inputModel.tvec_grip1(0);
    inputModel.tvec_grip2(1) = inputModel.tvec_grip1(1);
    inputModel.tvec_grip2(2) = inputModel.tvec_grip1(2);

    /**** orientation ***/
    double grip_2_delta = theta_grip_1 - theta_grip_2;
    double grip_1_delta = theta_grip_1 + theta_grip_2;

    cos_theta = cos(grip_1_delta);
    sin_theta = sin(-grip_1_delta);

    cv::Mat gripper_1_ = (cv::Mat_<double>(3,3) << 1, 0, 0,
            0,cos_theta,-sin_theta,
            0, sin_theta, cos_theta);

    cv::Mat rot_grip_1(3,3,CV_64FC1);
    cv::Rodrigues(seed_pose.rvec_grip1, rot_grip_1);
    rot_grip_1 = gripper_1_ * rot_grip_1;

    cv::Rodrigues(rot_grip_1, inputModel.rvec_grip1 );

    /*gripper 2*/
    cos_theta = cos(grip_2_delta);
    sin_theta = sin(-grip_2_delta);

    cv::Mat gripper_2_ = (cv::Mat_<double>(3,3) << 1, 0, 0,
            0,cos_theta,-sin_theta,
            0, sin_theta, cos_theta);

    cv::Mat rot_grip_2(3,3,CV_64FC1);
    cv::Rodrigues(seed_pose.rvec_grip2, rot_grip_2);
    rot_grip_2 = gripper_2_ * rot_grip_2;

    cv::Rodrigues(rot_grip_2, inputModel.rvec_grip2 );
};

/*using cylinder pose to compute rest pose*/
void ToolModel::computeEllipsePose(toolModel &inputModel, const double &theta_ellipse, const double &theta_grip_1,
                                   const double &theta_grip_2) {

    cv::Mat I = cv::Mat::eye(3, 3, CV_64FC1);
    /*********** computations for ellipse kinematics **********/
    ///take cylinder part as the origin
    cv::Mat q_temp(4, 1, CV_64FC1);

    cv::Mat q_ellipse_(4, 1, CV_64FC1);
    q_ellipse_.at<double>(0, 0) = 0;
    q_ellipse_.at<double>(1, 0) = 0.008;//0.011
    q_ellipse_.at<double>(2, 0) = 0;
    q_ellipse_.at<double>(3, 0) = 1;

    q_temp = transformPoints(q_ellipse_, cv::Mat(inputModel.rvec_cyl),
                             cv::Mat(inputModel.tvec_cyl)); //transform the ellipse coord according to cylinder pose

    inputModel.tvec_elp(0) = q_temp.at<double>(0, 0);
    inputModel.tvec_elp(1) = q_temp.at<double>(1, 0);
    inputModel.tvec_elp(2) = q_temp.at<double>(2, 0);

    cv::Mat rot_ellipse(3,3,CV_64FC1);
    cv::Rodrigues(inputModel.rvec_cyl, rot_ellipse);

    double cos_theta = cos(theta_ellipse);
    double sin_theta = sin(theta_ellipse);

    cv::Mat g_ellipse = (cv::Mat_<double>(3,3) << cos_theta, -sin_theta, 0,
            sin_theta, cos_theta, 0,
            0,0, 1);

    cv::Mat rot_new =  rot_ellipse * g_ellipse;
    cv::Mat temp_vec(3,1,CV_64FC1);
    cv::Rodrigues(rot_new, inputModel.rvec_elp);

    /*********** computations for gripper kinematics **********/
    cv::Mat test_gripper(3, 1, CV_64FC1);
    test_gripper.at<double>(0, 0) = 0;
    test_gripper.at<double>(1, 0) = 0.007;
    test_gripper.at<double>(2, 0) = 0;

    cv::Mat rot_elp(3, 3, CV_64FC1);
    cv::Rodrigues(inputModel.rvec_elp, rot_elp);  // get rotation mat of the ellipse

    cv::Mat q_rot(3, 1, CV_64FC1);
    q_rot = rot_elp * test_gripper;

    inputModel.tvec_grip1(0) = q_rot.at<double>(0, 0) + inputModel.tvec_elp(0);
    inputModel.tvec_grip1(1) = q_rot.at<double>(1, 0) + inputModel.tvec_elp(1);
    inputModel.tvec_grip1(2) = q_rot.at<double>(2, 0) + inputModel.tvec_elp(2);

    double theta_orien_grip = -1.0 * theta_grip_1; //maybe the x being flipped
    double theta_grip_open = theta_grip_2;
    if(theta_grip_open < 0.0){
        theta_grip_open = 0.0;
    }

    double grip_2_delta = theta_orien_grip - theta_grip_open;
    double grip_1_delta = theta_orien_grip + theta_grip_open;

    cos_theta = cos(grip_1_delta);
    sin_theta = sin(grip_1_delta);

    cv::Mat gripper_1_ = (cv::Mat_<double>(3,3) << 1, 0, 0,
            0,cos_theta,-sin_theta,
            0, sin_theta, cos_theta);

    cv::Mat rot_grip_1 = rot_elp * gripper_1_ ;
    cv::Rodrigues(rot_grip_1, inputModel.rvec_grip1);

    /*gripper 2*/
    inputModel.tvec_grip2(0) = inputModel.tvec_grip1(0);
    inputModel.tvec_grip2(1) = inputModel.tvec_grip1(1);
    inputModel.tvec_grip2(2) = inputModel.tvec_grip1(2);

    cos_theta = cos(grip_2_delta);
    sin_theta = sin(grip_2_delta);

    cv::Mat gripper_2_ = (cv::Mat_<double>(3,3) << 1, 0, 0,
            0,cos_theta,-sin_theta,
            0, sin_theta, cos_theta);

    cv::Mat rot_grip_2 = rot_elp * gripper_2_;
    cv::Rodrigues(rot_grip_2, inputModel.rvec_grip2);
};

cv::Mat ToolModel::computeSkew(cv::Mat &w) {
    cv::Mat skew(3, 3, CV_64FC1);
    skew.at<double>(0, 0) = 0;
    skew.at<double>(1, 0) = w.at<double>(2, 0);
    skew.at<double>(2, 0) = -w.at<double>(1, 0);
    skew.at<double>(0, 1) = -w.at<double>(2, 0);
    skew.at<double>(1, 1) = 0;
    skew.at<double>(2, 1) = w.at<double>(0, 0);
    skew.at<double>(0, 2) = w.at<double>(1, 0);
    skew.at<double>(1, 2) = -w.at<double>(0, 0);
    skew.at<double>(2, 2) = 0;

    return skew;

};

void ToolModel::computeInvSE(const cv::Mat &inputMat, cv::Mat &outputMat){

    outputMat = cv::Mat::eye(4,4,CV_64F);

    cv::Mat R = inputMat.colRange(0,3).rowRange(0,3);
    cv::Mat p = inputMat.colRange(3,4).rowRange(0,3);

    /*debug: opencv......*/
    cv::Mat R_rat = R.clone();
    cv::Mat p_tra = p.clone();

    R_rat = R_rat.t();  // rotation of inverse
    p_tra = -1 * R_rat * p_tra; // translation of inverse

    R_rat.copyTo(outputMat.colRange(0,3).rowRange(0,3));
    p_tra.copyTo(outputMat.colRange(3,4).rowRange(0,3));

}

void ToolModel::renderTool(cv::Mat &image, const toolModel &tool, cv::Mat &CamMat, const cv::Mat &P) {

    ComputeSilhouetteGPU(body_faces, body_neighbors, body_Vmat, body_Nmat, CamMat, image, cv::Mat(tool.rvec_cyl),
                       cv::Mat(tool.tvec_cyl), P);

//    ComputeSilhouetteGPU(ellipse_faces, ellipse_neighbors, ellipse_Vmat, ellipse_Nmat, CamMat, image,
//                       cv::Mat(tool.rvec_elp), cv::Mat(tool.tvec_elp), P, jac);
//
//    ComputeSilhouetteGPU(griper1_faces, griper1_neighbors, gripper1_Vmat, gripper1_Nmat, CamMat, image,
//                       cv::Mat(tool.rvec_grip1), cv::Mat(tool.tvec_grip1), P, jac);
//
//    ComputeSilhouetteGPU(griper2_faces, griper2_neighbors, gripper2_Vmat, gripper2_Nmat, CamMat, image,
//                       cv::Mat(tool.rvec_grip2), cv::Mat(tool.tvec_grip2), P, jac);


};

float ToolModel::calculateMatchingScore(cv::Mat &toolImage, const cv::Mat &segmentedImage) {

    float matchingScore;

    /*** When ROI is an empty rec, the position of tool is simply just not match, return 0 matching score ***/
    cv::Mat ROI_toolImage = toolImage.clone(); //(ROI); //crop tool image
    cv::Mat segImageGrey = segmentedImage.clone(); //(ROI); //crop segmented image, notice the size of the segmented image

    segImageGrey.convertTo(segImageGrey, CV_32FC1);
    cv::Mat segImgBlur;
    cv::GaussianBlur(segImageGrey,segImgBlur, cv::Size(9,9),4,4);
    segImgBlur /= 255; //scale the blurred image

    cv::Mat toolImageGrey; //grey scale of toolImage since tool image has 3 channels
    cv::Mat toolImFloat; //Float data type of grey scale tool image

    cv::cvtColor(ROI_toolImage, toolImageGrey, CV_BGR2GRAY); //convert it to grey scale

    toolImageGrey.convertTo(toolImFloat, CV_32FC1); // convert grey scale to float
    cv::Mat result(1, 1, CV_32FC1);

    cv::matchTemplate(segImgBlur, toolImFloat, result, CV_TM_CCORR_NORMED); //seg, toolImg
    matchingScore = static_cast<float> (result.at<float>(0));

    return matchingScore;
}

/*** chamfer matching algorithm, using distance transform, generate measurement model for PF ***/
float ToolModel::calculateChamferScore(cv::Mat &toolImage, const cv::Mat &segmentedImage) {

    float output = 0;
    cv::Mat ROI_toolImage = toolImage.clone(); //CV_8UC3
    cv::Mat segImgGrey = segmentedImage.clone(); //CV_8UC1

    segImgGrey.convertTo(segImgGrey, CV_8UC1);

    /***tool image process**/
    cv::Mat toolImageGrey(ROI_toolImage.size(), CV_8UC1); //grey scale of toolImage since tool image has 3 channels
    cv::Mat toolImFloat(ROI_toolImage.size(), CV_32FC1); //Float data type of grey scale tool image
    cv::cvtColor(ROI_toolImage, toolImageGrey, CV_BGR2GRAY); //convert it to grey scale

    toolImageGrey.convertTo(toolImFloat, CV_32FC1); // get float img

    cv::Mat BinaryImg(toolImFloat.size(), toolImFloat.type());
    BinaryImg = toolImFloat * (1.0/255);

    /***segmented image process**/
    for (int i = 0; i < segImgGrey.rows; i++) {
        for (int j = 0; j < segImgGrey.cols; j++) {
            segImgGrey.at<uchar>(i,j) = 255 - segImgGrey.at<uchar>(i,j);

        }
    }

    cv::Mat normDIST;
    cv::Mat distance_img;
    cv::distanceTransform(segImgGrey, distance_img, CV_DIST_L2, 3);
    cv::normalize(distance_img, normDIST, 0.00, 1.00, cv::NORM_MINMAX);

//    cv::imshow("segImgGrey img", segImgGrey);
//    cv::imshow("Normalized img", normDIST);
////    cv::imshow("distance_img", distance_img);
//    cv::waitKey();

    /***multiplication process**/
    cv::Mat resultImg; //initialize
    cv::multiply(normDIST, BinaryImg, resultImg);

    for (int k = 0; k < resultImg.rows; ++k) {
        for (int i = 0; i < resultImg.cols; ++i) {

            double mul = resultImg.at<float>(k,i);
            if(mul > 0.0)
                output += mul;
        }
    }
    //ROS_INFO_STREAM("OUTPUT: " << output);
    output = exp(-1 * output/80);

    return output;

};

cv::Point2d ToolModel::reproject(const cv::Mat &point, const cv::Mat &P) {
    cv::Mat results(3, 1, CV_64FC1);
    cv::Point2d output;

    cv::Mat ptMat(4, 1, CV_64FC1);
    ptMat.at<double>(0, 0) = point.at<double>(0, 0);
    ptMat.at<double>(1, 0) = point.at<double>(1, 0);
    ptMat.at<double>(2, 0) = point.at<double>(2, 0);
    ptMat.at<double>(3, 0) = 1.0;

    results = P * ptMat;
    output.x = results.at<double>(0, 0) / results.at<double>(2, 0);
    output.y = results.at<double>(1, 0) / results.at<double>(2, 0);

    return output;
};

void ToolModel::ComputeSilhouetteGPU(std::vector<int> &input_faces,
                                     std::vector<int> &neighbor_faces,
                                     const cv::Mat &input_Vmat, const cv::Mat &input_Nmat,
                                     cv::Mat &CamMat, cv::Mat &image, const cv::Mat &rvec, const cv::Mat &tvec,
                                     const cv::Mat &P){
    cv::cuda::GpuMat temp(4, 1, CV_64FC1);
    cv::Mat ept_1(4, 1, CV_64FC1);
    cv::Mat ept_2(4, 1, CV_64FC1);

    cv::Mat new_Vertices = transformPoints(input_Vmat, rvec, tvec);
    new_Vertices = camTransformMats(CamMat, new_Vertices); //transform every point under camera frame
    cv::Mat new_Normals = transformPoints(input_Nmat, rvec, tvec);
    new_Normals = camTransformMats(CamMat, new_Normals); //transform every surface normal under camera frame

    /**
     * starting parallel computing
     */
    int sizeOfFace = input_faces.size()/6;

    std::vector<int> *h_input_faces = &input_faces;

    int *d_input_faces;
    cudaMalloc((void **) &d_input_faces, sizeof(int) * sizeOfFace);  //I think is how many copies you want, instead of the size of the array
    cudaMemcpy(d_input_faces, h_input_faces, sizeof(int) * sizeOfFace, cudaMemcpyHostToDevice);

    std::vector<int> *h_neighbor_faces = &neighbor_faces;

    int *d_neighbor_faces;
    cudaMalloc((void **) &d_neighbor_faces, sizeof(int) * sizeOfFace);
    cudaMemcpy(d_neighbor_faces, h_neighbor_faces, sizeof(int) * sizeOfFace, cudaMemcpyHostToDevice);

    int * ind;
    cudaMalloc((void **) &ind, sizeof(int)* sizeOfFace);

    //copy inputs to gpuMats to send to kernel
    //Todo input_faces, neighbor_faces to GPU with boost
    cv::cuda::GpuMat host_new_Vertices;
    cv::cuda::GpuMat host_new_Normals;
    //host_new_Vertices.create(new_Vertices.rows, new_Vertices.cols,CV_64FC1 );

    host_new_Vertices.upload(new_Vertices);
    host_new_Normals.upload(new_Normals);

    renderingkernel<<<2, sizeOfFace/2>>>(host_new_Vertices, host_new_Normals, d_input_faces, d_neighbor_faces, ind );

    int *h_ind = 0;
//    cudaMalloc((void **) &h_ind, sizeof(int) * sizeOfFace*2);
    h_ind = (int *)malloc(sizeof(int) * sizeOfFace);

    cudaMemcpy(h_ind, ind, sizeof(int) * sizeOfFace*2, cudaMemcpyDeviceToHost);
    for (int i = 0; i < sizeOfFace; ++i) {
        printf(" the index is %d" , h_ind[i]);
    }

    int i =0;
    while(i < sizeOfFace){

        if (h_ind[i]!=0 &&h_ind[i+1]!=0)
        {
            ROS_INFO_STREAM("i1: "<<h_ind[i]);
            ROS_INFO_STREAM("i2: "<< h_ind[i+1]);
            new_Vertices.col(neighbor_faces[h_ind[0]]).copyTo(ept_1);
            new_Vertices.col(neighbor_faces[h_ind[1]]).copyTo(ept_2);


            cv::Point2d prjpt_1 = reproject(ept_1, P);
            cv::Point2d prjpt_2 = reproject(ept_2, P);


            if (prjpt_1.x <= 640 && prjpt_1.x >= -100 && prjpt_2.x < 640 && prjpt_2.x >= -100) {
                cv::line(image, prjpt_1, prjpt_2, cv::Scalar(255, 255, 255), 1, 8, 0);
            }
        }
        i +=2;
    }


};

__global__ void renderingkernel(cv::cuda::PtrStepSzf new_Vertices, cv::cuda::PtrStepSzf new_Normals, int  * input_faces,
                                int  * neighbor_faces, int * ind)
{
    //Find indices of vertices and normals for current
    int face_idx = threadIdx.x + blockIdx.x * blockDim.x;
    int v1 = input_faces[6* face_idx + 0];
    int v2 = input_faces[6* face_idx + 1];
    int v3 = input_faces[6* face_idx + 2];
    int n1 = input_faces[6* face_idx + 3];
    int n2 = input_faces[6* face_idx + 4];
    int n3 = input_faces[6* face_idx + 5];

    //Find the vertices and normals from the gpumat using the indices
    double3 pt1;
    pt1.x = new_Vertices(v1,0); pt1.y = new_Vertices(v1,1); pt1.z = new_Vertices(v1,2);

    double3 pt2;
    pt2.x = new_Vertices(v2,0); pt2.y = new_Vertices(v2,1); pt2.z = new_Vertices(v2,2);

    double3 pt3;
    pt3.x = new_Vertices(v3,0); pt3.y = new_Vertices(v3,1); pt3.z = new_Vertices(v3,2);

    double3 vn1;
    vn1.x = new_Vertices(n1,0); vn1.y = new_Vertices(n1,1); vn1.z = new_Vertices(n1,2);

    double3 vn2;
    vn2.x = new_Vertices(n2,0); vn2.y = new_Vertices(n2,1); vn2.z = new_Vertices(n2,2);

    double3 vn3;
    vn3.x = new_Vertices(n3,0); vn3.y = new_Vertices(n3,1); vn3.z = new_Vertices(n3,2);

    //compute face normal using 6 points
    double3 fnormal = FindFaceNormalGPU(pt1, pt2, pt3, vn1, vn2, vn3);
    double3 face_point_i;
    face_point_i.x= (pt1.x + pt2.x + pt3.x)/3;
    face_point_i.y= (pt1.y + pt2.y + pt3.y)/3;
    face_point_i.z= (pt1.z + pt2.z + pt3.z)/3;

    double isfront_i = dotProductGPU(fnormal, face_point_i);

    if(isfront_i < 0.000)
    {
        for (int neighbor_count = 0; neighbor_count < 3; ++neighbor_count)
        {  //notice: cannot use J here, since the last j will not be counted
            int j = 5 * neighbor_count;
            if(neighbor_faces[15*face_idx + j] >0) {
                int v1_ = input_faces[neighbor_faces[15 * face_idx + j] + 0];
                int v2_ = input_faces[neighbor_faces[15 * face_idx + j] + 1];
                int v3_ = input_faces[neighbor_faces[15 * face_idx + j] + 2];

                int n1_ = input_faces[neighbor_faces[15 * face_idx + j] + 3];
                int n2_ = input_faces[neighbor_faces[15 * face_idx + j] + 4];
                int n3_ = input_faces[neighbor_faces[15 * face_idx + j] + 5];


                double3 pt1_;
                pt1_.x = new_Vertices(v1_, 0);
                pt1_.y = new_Vertices(v1_, 1);
                pt1_.z = new_Vertices(v1_, 2);

                double3 pt2_;
                pt2_.x = new_Vertices(v2_, 0);
                pt2_.y = new_Vertices(v2_, 1);
                pt2_.z = new_Vertices(v2_, 2);

                double3 pt3_;
                pt3_.x = new_Vertices(v3_, 0);
                pt3_.y = new_Vertices(v3_, 1);
                pt3_.z = new_Vertices(v3_, 2);

                double3 vn1_;
                vn1_.x = new_Vertices(n1_, 0);
                vn1_.y = new_Vertices(n1_, 1);
                vn1_.z = new_Vertices(n1_, 2);

                double3 vn2_;
                vn2_.x = new_Vertices(n2_, 0);
                vn2_.y = new_Vertices(n2_, 1);
                vn2_.z = new_Vertices(n2_, 2);

                double3 vn3_;
                vn3_.x = new_Vertices(n3_, 0);
                vn3_.y = new_Vertices(n3_, 1);
                vn3_.z = new_Vertices(n3_, 2);

                double3 fnormal_n = FindFaceNormalGPU(pt1_, pt2_, pt3_, vn1_, vn2_, vn3_);
                double3 face_point_j;
                face_point_j.x= (pt1_.x + pt2_.x + pt3_.x)/3;
                face_point_j.y= (pt1_.y + pt2_.y + pt3_.y)/3;
                face_point_j.z= (pt1_.z + pt2_.z + pt3_.z)/3;

                double isfront_j = dotProductGPU(fnormal_n, face_point_j);

                if (isfront_i * isfront_j <= 0.0) // one is front, another is back
                {
                    //meant to save the points
                    ind[face_idx] = (15 * face_idx) + j + 1;
                    ind[face_idx+ 1] = (15 * face_idx) + j + 3;

                }
            }
        }
    }
}


__device__ double dotProductGPU(double3 &vec1, double3 &vec2) {
    double dot_res;
    dot_res = vec1.x * vec2.x + vec1.y * vec2.y + vec1.z * vec2.z;

    return dot_res;
};


__device__ double3 FindFaceNormalGPU(double3 &input_v1, double3 &input_v2, double3 &input_v3,
                                        double3 &input_n1, double3 &input_n2, double3 &input_n3)
{
    double3 temp_v1;
    double3 temp_v2;

    temp_v1.x = input_v1.x - input_v2.x;    //let temp v1 be v1-v2
    temp_v1.y = input_v1.y - input_v2.y;
    temp_v1.z = input_v1.z - input_v2.z;

    temp_v2.x = input_v1.x - input_v3.x;    //let temp v1 be v1-v3
    temp_v2.y = input_v1.y - input_v3.y;
    temp_v2.z = input_v1.z - input_v3.z;

    double3 res = crossProductGPU(temp_v1, temp_v2);

    double outward_normal_1 = dotProductGPU(res, input_n1);
    double outward_normal_2 = dotProductGPU(res, input_n2);
    double outward_normal_3 = dotProductGPU(res, input_n3);
    if ((outward_normal_1 < 0) || (outward_normal_2 < 0) || (outward_normal_3 < 0))
    {
        res.x = -1 * res.x;
        res.y= -1 * res.y;
        res.z = -1 * res.z;
    }

    return res;  // knowing the direction

};


__device__ double3 crossProductGPU(double3 &vec1, double3 &vec2)
{    //3d vector

    double3 res_vec;
    res_vec.x = vec1.y * vec2.z - vec1.z * vec2.y;
    res_vec.y = vec1.z * vec2.x - vec1.x * vec2.z;
    res_vec.z = vec1.x * vec2.y - vec1.y * vec2.x;

    return res_vec;
};


//__device__ double dotProd (cv::cuda::PtrStepSz<float2> vec1, cv::cuda::PtrStepSz<float2> vec2)
//{
//    int x = threadIdx.x + blockIdx.x * blockDim.x;
//    int y = threadIdx.y + blockIdx.y * blockDim.y;
//    double xP(vec1(y, x).x * vec2(y, x).x);
//    double yP(vec1(y, x).y * vec2(y, x).y);
//    return (xP + yP);
//}
