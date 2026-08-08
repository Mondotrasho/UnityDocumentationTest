using UnityEngine;

namespace DocumentationGeneration.Example
{
    /// <summary>
    /// Smallish Unity component used to prove that standard C# XML comments
    /// can become generated API documentation automatically.
    /// </summary>
    public class DocumentationExample : MonoBehaviour
    {
        /// <summary>
        /// Gets the object currently assigned as this component's target.
        /// </summary>
        public GameObject Target { get; private set; }

	/// <summary>
	/// Assigns the GameObject that this component should track.
	/// </summary>
        /// <param name="target">The Unity object that should become the current target.</param>
        public void SetTarget(GameObject target)
        {
            Target = target;
        }

        /// <summary>
        /// Returns the distance from this component to the current target.
        /// </summary>
        /// <returns>
        /// The distance in Unity world units, or zero when no target is assigned.
        /// </returns>
        public float GetDistanceToTarget()
        {
            if (Target == null)
            {
                return 0f;
            }

            return Vector3.Distance(transform.position, Target.transform.position);
        }
    }
}

