import Foundation

/// How many layers go to the GPU. Metal can only hold about three quarters of RAM ("recommended working set"), so a model
/// larger than that keeps the rest of its layers on the CPU, read through mmap.
enum GPUOffload {
    /// The share of the GPU working set the weights may use. KV cache and compute buffers need the rest.
    static let weightShare = 0.75

    /// `gpuBudgetBytes` is nil where there is no limit to respect. The result counts the output layer, so `blockCount + 1` is "all".
    static func layers(blockCount: Int, fileBytes: Int64, gpuBudgetBytes: Int64?) -> Int32 {
        let all = Int32(clamping: blockCount + 1)
        guard let gpuBudgetBytes, blockCount > 0, fileBytes > 0 else { return all }
        let weightBudget = Double(gpuBudgetBytes) * weightShare
        guard Double(fileBytes) > weightBudget else { return all }
        let share = weightBudget / Double(fileBytes)
        return Int32(max(0, (Double(blockCount) * share).rounded(.down)))
    }
}
